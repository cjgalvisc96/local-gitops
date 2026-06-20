#!/usr/bin/env bash
# =============================================================================
# GitOps Enterprise Lab — one-command installer
#
# Builds a 3-cluster local GitOps platform:
#   management : Gitea + Argo CD (the control plane)
#   dev / prod : applications + OpenTelemetry + Prometheus + Grafana (GitOps-managed)
#
# Follows the steps in NEXT-STEPS.md (0..10). Idempotent: safe to re-run.
# =============================================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

# -----------------------------------------------------------------------------
# 0. Verify dependencies (Docker, Git, Curl)
# -----------------------------------------------------------------------------
check_deps() {
  step "0. Verifying dependencies"
  local missing=0
  for d in docker git curl; do
    if require_cmd "$d"; then log "found: $d"; else err "missing required dependency: $d"; missing=1; fi
  done
  [ "$missing" -eq 0 ] || die "Install the missing dependencies and re-run."
  docker info >/dev/null 2>&1 || die "Docker daemon is not reachable (is it running / are you in the docker group?)."
}

# -----------------------------------------------------------------------------
# 1. Install missing tools (kubectl, kind, helm, k9s, argocd)
# -----------------------------------------------------------------------------
install_tools() {
  step "1. Installing missing tools"
  local arch; arch="$(uname -m)"; [ "$arch" = "x86_64" ] && arch="amd64"; [ "$arch" = "aarch64" ] && arch="arm64"
  local os; os="$(uname | tr '[:upper:]' '[:lower:]')"

  if ! require_cmd kubectl; then
    log "installing kubectl ${KUBECTL_VERSION}"
    curl -sSLf "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${os}/${arch}/kubectl" -o /tmp/kubectl
    sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  fi
  if ! require_cmd kind; then
    log "installing kind"
    curl -sSLf "https://kind.sigs.k8s.io/dl/v0.24.0/kind-${os}-${arch}" -o /tmp/kind
    sudo install -m 0755 /tmp/kind /usr/local/bin/kind
  fi
  if ! require_cmd helm; then
    log "installing helm"
    curl -sSLf https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  if ! require_cmd k9s; then
    log "installing k9s"
    curl -sSLf "https://github.com/derailed/k9s/releases/latest/download/k9s_$(uname)_${arch}.tar.gz" -o /tmp/k9s.tgz
    tar -xzf /tmp/k9s.tgz -C /tmp k9s
    sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s
  fi
  if ! require_cmd argocd; then
    log "installing argocd CLI"
    curl -sSLf "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-${os}-${arch}" -o /tmp/argocd
    sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
  fi
  if ! require_cmd aws; then
    if require_cmd unzip; then
      log "installing AWS CLI v2 (for floci seeding)"
      curl -sSLf "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip
      unzip -q -o /tmp/awscliv2.zip -d /tmp
      sudo /tmp/aws/install --update
    else
      warn "aws CLI and unzip both missing; floci SSM/ECR seeding will be skipped"
    fi
  fi
}

# -----------------------------------------------------------------------------
# Local AWS 'floci' profile in ~/.aws (created by default, idempotent)
# -----------------------------------------------------------------------------
setup_aws_profile() {
  step "Configuring local AWS '${AWS_PROFILE_NAME}' profile (~/.aws)"
  local cfg="$HOME/.aws/config" creds="$HOME/.aws/credentials"
  mkdir -p "$HOME/.aws"
  if grep -q "^\[profile ${AWS_PROFILE_NAME}\]" "$cfg" 2>/dev/null; then
    log "profile '${AWS_PROFILE_NAME}' already in ~/.aws/config"
  else
    cat >>"$cfg" <<EOF

[profile ${AWS_PROFILE_NAME}]
region = ${AWS_REGION}
output = json
endpoint_url = ${FLOCI_HOST_ENDPOINT}
EOF
    log "added [profile ${AWS_PROFILE_NAME}] to ~/.aws/config"
  fi
  if grep -q "^\[${AWS_PROFILE_NAME}\]" "$creds" 2>/dev/null; then
    log "profile '${AWS_PROFILE_NAME}' already in ~/.aws/credentials"
  else
    cat >>"$creds" <<EOF

[${AWS_PROFILE_NAME}]
aws_access_key_id = test
aws_secret_access_key = test
EOF
    chmod 600 "$creds"
    log "added [${AWS_PROFILE_NAME}] to ~/.aws/credentials"
  fi
}

# -----------------------------------------------------------------------------
# floci (local AWS) — start the emulator container
# -----------------------------------------------------------------------------
setup_floci() {
  step "Setting up floci (local AWS emulator)"
  if docker ps --format '{{.Names}}' | grep -qx "$FLOCI_CONTAINER"; then
    log "floci already running"
  else
    docker rm -f "$FLOCI_CONTAINER" >/dev/null 2>&1 || true
    log "starting floci container ($FLOCI_IMAGE) on :$FLOCI_PORT"
    docker run -d --name "$FLOCI_CONTAINER" \
      -p "${FLOCI_PORT}:${FLOCI_PORT}" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -u root \
      "$FLOCI_IMAGE" >/dev/null
  fi
  log "waiting for floci endpoint ${FLOCI_HOST_ENDPOINT} ..."
  for _ in $(seq 1 40); do
    curl -sf "${FLOCI_HOST_ENDPOINT}" >/dev/null 2>&1 && { log "floci is up"; return; }
    sleep 3
  done
  warn "floci did not become ready in time; SSM-backed secrets may stay Missing"
}

# -----------------------------------------------------------------------------
# 2. Create clusters (management, dev, prod)
# -----------------------------------------------------------------------------
create_clusters() {
  step "2. Creating kind clusters"
  for c in "${CLUSTERS[@]}"; do
    if kind get clusters 2>/dev/null | grep -qx "$c"; then
      log "cluster '$c' already exists"
    else
      log "creating cluster '$c'"
      kind create cluster --name "$c" --image "$NODE_IMAGE" --config "clusters/$c.yaml" --wait 120s
    fi
  done
}

# -----------------------------------------------------------------------------
# 3. Install MetalLB (all clusters, non-overlapping pools)
# -----------------------------------------------------------------------------
install_metallb() {
  step "3. Installing MetalLB on all clusters"
  local pools=("$MGMT_POOL" "$DEV_POOL" "$PROD_POOL")
  local i=0
  for c in "${CLUSTERS[@]}"; do
    log "[$c] applying MetalLB ${METALLB_VERSION}"
    kc "$c" apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"
    kc "$c" wait --for=condition=Available deploy/controller -n metallb-system --timeout=180s
    kc "$c" wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=120s
    log "[$c] configuring address pool ${pools[$i]}"
    kc "$c" apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: pool
  namespace: metallb-system
spec:
  addresses:
    - ${pools[$i]}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - pool
EOF
    i=$((i+1))
  done
}

# -----------------------------------------------------------------------------
# 4. Install ingress-nginx (all clusters)
# -----------------------------------------------------------------------------
install_ingress() {
  step "4. Installing ingress-nginx on all clusters"
  for c in "${CLUSTERS[@]}"; do
    log "[$c] installing ingress-nginx ${INGRESS_NGINX_VERSION}"
    helm --kube-context "$(ctx "$c")" upgrade --install ingress-nginx ingress-nginx \
      --repo https://kubernetes.github.io/ingress-nginx \
      --version "$INGRESS_NGINX_VERSION" \
      --namespace ingress-nginx --create-namespace \
      -f bootstrap/ingress-nginx/values.yaml \
      --wait --timeout 300s
  done
}

# -----------------------------------------------------------------------------
# 5. Install Gitea (management) + seed GitOps repos
# -----------------------------------------------------------------------------
install_gitea() {
  step "5. Installing Gitea on the management cluster"
  helm repo add gitea https://dl.gitea.com/charts >/dev/null 2>&1 || true
  helm repo update gitea >/dev/null
  helm --kube-context "$(ctx "$MGMT_CLUSTER")" upgrade --install gitea gitea/gitea \
    --version "$GITEA_CHART_VERSION" \
    --namespace gitea --create-namespace \
    -f bootstrap/gitea/values.yaml \
    --wait --timeout 600s
  kc "$MGMT_CLUSTER" apply -f bootstrap/gitea/ingress.yaml
  # Pinned LB so the dev/prod Argo instances can clone Gitea cross-cluster.
  kc "$MGMT_CLUSTER" apply -f bootstrap/gitea/git-lb.yaml
  seed_gitea
}

seed_gitea() {
  log "seeding Gitea org '${GITEA_ORG}' and GitOps repos"
  # Port-forward the Gitea API/HTTP to localhost for setup.
  kc "$MGMT_CLUSTER" -n gitea port-forward svc/gitea-http 3000:3000 >/tmp/gitea-pf.log 2>&1 &
  local pf=$!
  trap 'kill '"$pf"' >/dev/null 2>&1 || true' RETURN
  local base="http://localhost:3000"
  local auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}"

  log "waiting for Gitea API..."
  for _ in $(seq 1 60); do
    curl -sf "${base}/api/v1/version" >/dev/null 2>&1 && break
    sleep 3
  done

  # Org (ignore 'already exists').
  curl -sf -u "$auth" -X POST "${base}/api/v1/orgs" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${GITEA_ORG}\"}" >/dev/null 2>&1 || true

  # Lab repos that live inside this repo (platform-config, gitops-apps).
  for repo in "${GITEA_REPOS[@]}"; do
    create_gitea_repo "$repo" "$auth" "$base"
    push_repo "$repo" "${REPO_ROOT}/${repo}"
  done
  # The application repo (external git repo with its own Helm chart) — only when
  # the app deployment is enabled.
  if [ "$DEPLOY_APP" = "true" ]; then
    if [ -d "$APP_REPO_PATH" ]; then
      create_gitea_repo "$APP_REPO_NAME" "$auth" "$base"
      push_app_repo
    else
      warn "app repo not found at $APP_REPO_PATH; skipping (set APP_REPO_PATH)"
    fi
  else
    log "DEPLOY_APP=false; skipping todo-app repo mirror"
  fi
  kill "$pf" >/dev/null 2>&1 || true
  trap - RETURN
}

create_gitea_repo() {
  local repo="$1" auth="$2" base="$3"
  curl -sf -u "$auth" -X POST "${base}/api/v1/orgs/${GITEA_ORG}/repos" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${repo}\",\"private\":false,\"auto_init\":false}" >/dev/null 2>&1 || true
}

# push_repo <repo-name> <local-src-dir>  — snapshot a directory as a fresh repo.
push_repo() {
  local repo="$1" src="$2"
  [ -d "$src" ] || { warn "missing source dir for repo '$repo'"; return; }
  log "pushing '$repo' to Gitea"
  local tmp; tmp="$(mktemp -d)"
  cp -r "$src/." "$tmp/"
  # When the app deployment is disabled, don't ship the todo-app / dependency
  # Applications, so the per-cluster Argo never deploys them.
  if [ "$repo" = "platform-config" ] && [ "$DEPLOY_APP" != "true" ]; then
    rm -f "$tmp"/envs/*/todo-app.yaml "$tmp"/envs/*/dependencies.yaml
    log "  (DEPLOY_APP=false: omitting todo-app + dependencies)"
  fi
  (
    cd "$tmp"
    git init -q -b main
    git config user.email "installer@gitops.local"
    git config user.name "installer"
    git add -A
    git commit -q -m "chore: seed ${repo} from install.sh"
    git push -qf "http://${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}@localhost:3000/${GITEA_ORG}/${repo}.git" main
  )
  rm -rf "$tmp"
}

# Mirror the application repo's tracked files (respecting its .gitignore) to Gitea.
push_app_repo() {
  log "mirroring app repo '${APP_REPO_NAME}' (tracked files) to Gitea"
  local tmp; tmp="$(mktemp -d)"
  git -C "$APP_REPO_PATH" archive --format=tar HEAD | tar -x -C "$tmp" 2>/dev/null \
    || { warn "could not archive $APP_REPO_PATH (is it a git repo with commits?)"; rm -rf "$tmp"; return; }
  (
    cd "$tmp"
    git init -q -b main
    git config user.email "installer@gitops.local"
    git config user.name "installer"
    git add -A
    git commit -q -m "chore: mirror ${APP_REPO_NAME} from install.sh"
    git push -qf "http://${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}@localhost:3000/${GITEA_ORG}/${APP_REPO_NAME}.git" main
  )
  rm -rf "$tmp"
}

# -----------------------------------------------------------------------------
# 6. Install Argo CD in EACH workload cluster (one Argo per env)
# -----------------------------------------------------------------------------
install_argocd() {
  step "6. Installing Argo CD in the dev & prod clusters"
  for c in "${ARGO_CLUSTERS[@]}"; do
    log "[$c] installing Argo CD ${ARGOCD_VERSION}"
    kc "$c" create namespace argocd --dry-run=client -o yaml | kc "$c" apply -f -
    kc "$c" apply -n argocd \
      -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    kc "$c" apply -f bootstrap/argocd/argocd-cmd-params.yaml
    kc "$c" apply -f bootstrap/argocd/argocd-rbac.yaml
    kc "$c" apply -f "bootstrap/argocd/ingress-${c}.yaml"
    kc "$c" wait --for=condition=Established crd/applications.argoproj.io --timeout=180s
    kc "$c" -n argocd rollout restart deploy/argocd-server
    kc "$c" -n argocd rollout status deploy/argocd-server --timeout=300s
  done
}

# -----------------------------------------------------------------------------
# 7. Build the app image and load it into the dev & prod clusters
# -----------------------------------------------------------------------------
build_and_load_image() {
  step "7. Building & loading the todo-app image"
  if [ "$DEPLOY_APP" != "true" ]; then
    log "DEPLOY_APP=false; skipping app image build (set DEPLOY_APP=true to deploy)"
    return
  fi
  if [ ! -d "$APP_REPO_PATH" ]; then
    warn "app repo not found at $APP_REPO_PATH; skipping image build"
    return
  fi
  for tag in dev prod; do
    log "building ${APP_IMAGE}:${tag}"
    docker build -t "${APP_IMAGE}:${tag}" "$APP_REPO_PATH" >/dev/null \
      || { warn "image build failed for ${APP_IMAGE}:${tag}"; return; }
  done
  # dev cluster runs :dev, prod cluster runs :prod (both loaded so either works).
  for c in "${ARGO_CLUSTERS[@]}"; do
    for tag in dev prod; do
      log "[$c] loading ${APP_IMAGE}:${tag}"
      kind load docker-image "${APP_IMAGE}:${tag}" --name "$c" >/dev/null 2>&1 || true
    done
  done
}

# -----------------------------------------------------------------------------
# 8. Bootstrap each cluster's root Application (app-of-apps)
# -----------------------------------------------------------------------------
bootstrap_root() {
  step "8. Bootstrapping per-cluster root Applications"
  for c in "${ARGO_CLUSTERS[@]}"; do
    log "[$c] applying root app (envs/$c)"
    kc "$c" apply -f "bootstrap/argocd/root-${c}.yaml"
  done
  log "Each Argo CD now reconciles its env from platform-config/envs/<env>."
}

# -----------------------------------------------------------------------------
# floci (local AWS) — best-effort seeding of SSM parameters
# -----------------------------------------------------------------------------
seed_floci() {
  step "Seeding floci (SSM parameters + ECR registry)"
  if ! require_cmd aws; then warn "aws CLI not found; skipping floci seeding"; return; fi
  local ep="$FLOCI_HOST_ENDPOINT"
  if ! curl -sf "${ep}" >/dev/null 2>&1; then warn "floci not reachable at ${ep}; skipping seeding"; return; fi
  # Use the local 'floci' profile created by setup_aws_profile.
  export AWS_PROFILE="$AWS_PROFILE_NAME"

  # SSM params consumed by the todo-app's ExternalSecret (/gitops/<env>/todo-app/*).
  # Values match the postgres/redis dependencies the platform deploys.
  for env in dev prod; do
    local pfx="/gitops/${env}/todo-app"
    aws --endpoint-url "$ep" ssm put-parameter --overwrite --type String \
      --name "${pfx}/DB_USER" --value "todo" >/dev/null 2>&1 || true
    aws --endpoint-url "$ep" ssm put-parameter --overwrite --type SecureString \
      --name "${pfx}/DB_PASSWORD" --value "todo" >/dev/null 2>&1 || true
    aws --endpoint-url "$ep" ssm put-parameter --overwrite --type SecureString \
      --name "${pfx}/REDIS_PASSWORD" --value "redispass" >/dev/null 2>&1 || true
    log "ssm: ${pfx}/{DB_USER,DB_PASSWORD,REDIS_PASSWORD}"
  done

  # ECR repo (the lab's "docker images register using AWS ECR").
  aws --endpoint-url "$ep" ecr create-repository --repository-name "gitops/todo-app" \
    >/dev/null 2>&1 && log "ecr: gitops/todo-app" || true
}

# -----------------------------------------------------------------------------
# DNS — dnsmasq + systemd-resolved (fallback: /etc/hosts), no manual edits
# -----------------------------------------------------------------------------
lb_ip() { kc "$1" -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null; }

wait_lb_ip() {
  local c="$1" ip=""
  for _ in $(seq 1 60); do ip="$(lb_ip "$c")"; [ -n "$ip" ] && { echo "$ip"; return; }; sleep 3; done
  return 1
}

setup_dns() {
  step "10a. Configuring local DNS"
  MGMT_IP="$(wait_lb_ip "$MGMT_CLUSTER")" || die "management ingress never got a LoadBalancer IP"
  DEV_IP="$(wait_lb_ip "$DEV_CLUSTER")"   || die "dev ingress never got a LoadBalancer IP"
  PROD_IP="$(wait_lb_ip "$PROD_CLUSTER")" || die "prod ingress never got a LoadBalancer IP"
  log "ingress IPs  mgmt=$MGMT_IP  dev=$DEV_IP  prod=$PROD_IP"

  # Host -> IP map. Gitea is on management; each env's Argo + apps live in that
  # env's own cluster, so argo/grafana/todo-app.<env>.local point at <env>'s ingress.
  declare -A HOSTS=(
    [gitea.dev.local]="$MGMT_IP"
    [argo.dev.local]="$DEV_IP"
    [grafana.dev.local]="$DEV_IP"
    [todo-app.dev.local]="$DEV_IP"
    [argo.prod.local]="$PROD_IP"
    [grafana.prod.local]="$PROD_IP"
    [todo-app.prod.local]="$PROD_IP"
  )

  # System-level split DNS via dnsmasq + systemd-resolved (so the whole host,
  # CLIs, etc. resolve the lab domains)...
  if require_cmd dnsmasq && systemctl is-active --quiet systemd-resolved; then
    setup_dns_dnsmasq
  else
    warn "dnsmasq or systemd-resolved unavailable; relying on /etc/hosts only"
  fi
  # ...AND /etc/hosts, because browsers with "Secure DNS"/DoH bypass the system
  # resolver and would otherwise never reach dnsmasq. /etc/hosts is honored
  # regardless, so the UIs work in the browser without disabling DoH.
  setup_dns_hosts
}

setup_dns_dnsmasq() {
  log "writing dnsmasq config ${DNS_CONFFILE}"
  {
    echo "port=${DNS_PORT}"
    echo "listen-address=127.0.0.1"
    echo "bind-interfaces"
    echo "no-resolv"
    for h in "${!HOSTS[@]}"; do echo "address=/${h}/${HOSTS[$h]}"; done
  } >"$DNS_CONFFILE"

  # (re)start a dedicated dnsmasq instance.
  [ -f "$DNS_PIDFILE" ] && sudo kill "$(cat "$DNS_PIDFILE")" >/dev/null 2>&1 || true
  sudo dnsmasq --conf-file="$DNS_CONFFILE" --pid-file="$DNS_PIDFILE"
  log "dnsmasq listening on 127.0.0.1:${DNS_PORT}"

  log "routing *.dev.local / *.prod.local to dnsmasq via systemd-resolved"
  sudo mkdir -p "$(dirname "$RESOLVED_DROPIN")"
  sudo tee "$RESOLVED_DROPIN" >/dev/null <<EOF
# Managed by gitops-lab install.sh
[Resolve]
DNS=127.0.0.1:${DNS_PORT}
Domains=~dev.local ~prod.local
EOF
  sudo systemctl restart systemd-resolved
}

setup_dns_hosts() {
  log "updating /etc/hosts (gitops-lab block)"
  sudo sed -i '/# gitops-lab/d' /etc/hosts
  for h in "${!HOSTS[@]}"; do
    echo "${HOSTS[$h]} ${h} # gitops-lab" | sudo tee -a /etc/hosts >/dev/null
  done
}

# -----------------------------------------------------------------------------
# 10b. Print URLs / credentials
# -----------------------------------------------------------------------------
output() {
  step "Platform ready"
  local dev_pw prod_pw
  dev_pw="$(kc "$DEV_CLUSTER" -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  prod_pw="$(kc "$PROD_CLUSTER" -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  local dev_app="" prod_app=""
  if [ "$DEPLOY_APP" = "true" ]; then
    dev_app=$'\n    todo-app     http://todo-app.dev.local'
    prod_app=$'\n    todo-app     http://todo-app.prod.local'
  fi
  cat <<EOF

==================================================================
  🚀  GitOps Enterprise Lab is UP
==================================================================
  management cluster
    Gitea        http://gitea.dev.local         ($GITEA_ADMIN_USER / $GITEA_ADMIN_PASSWORD)
  DEV cluster (its own Argo CD)
    Argo CD      http://argo.dev.local          (admin / ${dev_pw:-<see below>})
    Grafana      http://grafana.dev.local       (admin / admin)${dev_app}
  PROD cluster (its own Argo CD)
    Argo CD      http://argo.prod.local         (admin / ${prod_pw:-<see below>})
    Grafana      http://grafana.prod.local      (admin / admin)${prod_app}
------------------------------------------------------------------
  Argo CD admin password (per cluster):
    kubectl --context kind-dev  -n argocd get secret argocd-initial-admin-secret \\
      -o jsonpath='{.data.password}' | base64 -d
    kubectl --context kind-prod -n argocd get secret argocd-initial-admin-secret \\
      -o jsonpath='{.data.password}' | base64 -d
  Tip:  k9s --context kind-dev   |   k9s --context kind-prod
==================================================================
EOF
}

# -----------------------------------------------------------------------------
main() {
  log "Starting GitOps Enterprise Lab install"
  check_deps             # 0
  install_tools          # 1
  setup_aws_profile      # local AWS 'floci' profile in ~/.aws
  setup_floci            # start floci (local AWS)
  seed_floci             # SSM params + ECR repo
  create_clusters        # 2  (management, dev, prod)
  install_metallb        # 3
  install_ingress        # 4
  install_gitea          # 5  (+ seed platform-config, gitops-apps, app repo)
  install_argocd         # 6  (one Argo per env: dev, prod)
  build_and_load_image   # 7  (todo-app image -> kind)
  bootstrap_root         # 8  (per-cluster app-of-apps)
  setup_dns              # 9
  output                 # 10
}

main "$@"
