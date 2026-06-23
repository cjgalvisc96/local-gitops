#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh
ensure_mise_path

check_deps() {
  step "0. Verifying dependencies"
  local missing=0
  for d in docker git curl; do
    if require_cmd "$d"; then log "found: $d"; else err "missing required dependency: $d"; missing=1; fi
  done
  [ "$missing" -eq 0 ] || die "Install the missing dependencies and re-run."
  docker info >/dev/null 2>&1 || die "Docker daemon is not reachable (is it running / are you in the docker group?)."
}

install_tools() {
  step "1. Installing the CLI toolchain via mise"

  if ! require_cmd mise && [ ! -x "$HOME/.local/bin/mise" ]; then
    log "installing mise (https://mise.run)"
    curl -sSf https://mise.run | sh
  fi
  ensure_mise_path
  require_cmd mise || die "mise install failed; see https://mise.jdx.dev for manual setup."
  log "mise $(mise --version 2>/dev/null) ready"

  mise trust "${REPO_ROOT}/mise.toml" >/dev/null 2>&1 || true
  log "installing pinned tools globally (mise use -g) — this can take a minute"
  local t
  while read -r t; do
    [ -z "$t" ] && continue
    log "  $t"
    mise use --global "$t" >/dev/null 2>&1 || warn "could not install $t (skipped)"
  done < <(mise_tool_args)
  mise reshim >/dev/null 2>&1 || true
  ensure_mise_path
  setup_mise_shell

  if ! require_cmd dnsmasq; then
    pkg_install dnsmasq || warn "could not install dnsmasq; DNS will fall back to /etc/hosts only"
  fi

  for t in kubectl kind helm argocd; do
    require_cmd "$t" || die "tool '$t' not on PATH after mise install (PATH=$PATH)"
  done
  require_cmd aws || warn "aws CLI not available; floci SSM/ECR seeding will be skipped"
}

setup_mise_shell() {
  local sh rc
  sh="$(basename "${SHELL:-bash}")"
  case "$sh" in
    zsh)  rc="$HOME/.zshrc" ;;
    fish) rc="$HOME/.config/fish/config.fish" ;;
    *)    rc="$HOME/.bashrc"; sh="bash" ;;
  esac
  if [ -f "$rc" ] && grep -q 'mise activate' "$rc" 2>/dev/null; then
    log "mise already activated in $rc"
    return
  fi
  mkdir -p "$(dirname "$rc")"
  if [ "$sh" = "fish" ]; then
    printf '\n# gitops-lab install.sh — activate global mise tools\nmise activate fish | source\n' >>"$rc"
  else
    printf '\n# gitops-lab install.sh — activate global mise tools\neval "$(mise activate %s)"\n' "$sh" >>"$rc"
  fi
  log "added 'mise activate $sh' to $rc — open a new shell (or 'exec $sh') to use the tools globally"
}

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
      --label "com.docker.compose.project=${PROJECT_NAME}" \
      --label "com.docker.compose.service=floci" \
      "$FLOCI_IMAGE" >/dev/null
  fi
  log "waiting for floci endpoint ${FLOCI_HOST_ENDPOINT} ..."
  for _ in $(seq 1 40); do
    curl -sf "${FLOCI_HOST_ENDPOINT}" >/dev/null 2>&1 && { log "floci is up"; return; }
    sleep 3
  done
  warn "floci did not become ready in time; SSM-backed secrets may stay Missing"
}

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

detect_network() {
  step "2b. Detecting kind network subnet"
  local subnet prefix
  subnet="$(docker network inspect kind --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' 2>/dev/null \
    | grep -E '^[0-9]+\.[0-9]+\.' | head -1)"
  if [ -z "$subnet" ]; then
    warn "could not read kind network subnet; assuming default ${DEFAULT_NET_PREFIX}.0.0/16"
    return
  fi
  prefix="$(echo "$subnet" | cut -d. -f1,2)"
  apply_net_prefix "$prefix"
  log "kind bridge ${subnet} -> prefix=${NET_PREFIX} gitea_lb=${GITEA_GIT_IP} floci_gw=${FLOCI_GW}"
  [ "$NET_PREFIX" != "$DEFAULT_NET_PREFIX" ] \
    && log "(differs from committed ${DEFAULT_NET_PREFIX}; manifests rewritten on apply/push)"
  return 0
}

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
  subst_net < bootstrap/gitea/git-lb.yaml | kc "$MGMT_CLUSTER" apply -f -
  seed_gitea
}

seed_gitea() {
  log "seeding Gitea org '${GITEA_ORG}' and GitOps repos"
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

  curl -sf -u "$auth" -X POST "${base}/api/v1/orgs" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${GITEA_ORG}\"}" >/dev/null 2>&1 || true

  for repo in "${GITEA_REPOS[@]}"; do
    create_gitea_repo "$repo" "$auth" "$base"
    push_repo "$repo" "${REPO_ROOT}/${repo}"
  done
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

push_repo() {
  local repo="$1" src="$2"
  [ -d "$src" ] || { warn "missing source dir for repo '$repo'"; return; }
  log "pushing '$repo' to Gitea"
  local tmp; tmp="$(mktemp -d)"
  cp -r "$src/." "$tmp/"
  if [ "$repo" = "platform-config" ] && [ "$DEPLOY_APP" != "true" ]; then
    # Keep only the core platform Applications; drop every app registration
    # (any other manifest in envs/*/). Keeps the platform app-agnostic.
    find "$tmp"/envs -type f -name '*.yaml' \
      ! -name 'project.yaml' ! -name 'platform.yaml' \
      ! -name 'observability.yaml' ! -name 'external-secrets.yaml' -delete
    log "  (DEPLOY_APP=false: keeping only core platform apps)"
  fi
  subst_net_tree "$tmp"
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
    register_gitea_repos "$c"
    kc "$c" -n argocd rollout restart deploy/argocd-server
    kc "$c" -n argocd rollout status deploy/argocd-server --timeout=300s
  done
}

register_gitea_repos() {
  local c="$1" repo
  local repos=("${GITEA_REPOS[@]}")
  [ "$DEPLOY_APP" = "true" ] && repos+=("$APP_REPO_NAME")
  log "[$c] linking Argo CD to Gitea (${GITEA_GIT_URL})"
  for repo in "${repos[@]}"; do
    kc "$c" apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: repo-${repo}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  name: ${repo}
  url: ${GITEA_GIT_URL}/${repo}.git
  username: ${GITEA_ADMIN_USER}
  password: ${GITEA_ADMIN_PASSWORD}
EOF
  done
}

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
  for c in "${ARGO_CLUSTERS[@]}"; do
    for tag in dev prod; do
      log "[$c] loading ${APP_IMAGE}:${tag}"
      kind load docker-image "${APP_IMAGE}:${tag}" --name "$c" >/dev/null 2>&1 || true
    done
  done
}

bootstrap_root() {
  step "8. Bootstrapping per-cluster root Applications"
  for c in "${ARGO_CLUSTERS[@]}"; do
    log "[$c] applying root app (envs/$c)"
    subst_net < "bootstrap/argocd/root-${c}.yaml" | kc "$c" apply -f -
  done
  log "Each Argo CD now reconciles its env from platform-config/envs/<env>."
}

seed_floci() {
  step "Seeding floci (per-app SSM parameters + ECR registry)"
  if ! require_cmd aws; then warn "aws CLI not found; skipping floci seeding"; return; fi
  local ep="$FLOCI_HOST_ENDPOINT"
  if ! curl -sf "${ep}" >/dev/null 2>&1; then warn "floci not reachable at ${ep}; skipping seeding"; return; fi

  # Apps own their floci state: each registered app declares it in its own
  # repo at infra/k8s/gitops/floci-seed.sh. The platform just runs it. Keeps
  # this script app-agnostic and scales to any number of apps.
  if [ "$DEPLOY_APP" != "true" ]; then
    log "DEPLOY_APP=false; no app floci state to seed"
    return
  fi
  local seed="${APP_REPO_PATH}/infra/k8s/gitops/floci-seed.sh"
  if [ -x "$seed" ]; then
    log "seeding floci for '${APP_REPO_NAME}' via its floci-seed.sh"
    AWS_ENDPOINT_URL="$ep" AWS_PROFILE="$AWS_PROFILE_NAME" AWS_REGION="$AWS_REGION" \
      "$seed" || warn "floci-seed.sh failed for ${APP_REPO_NAME}"
  else
    warn "no floci-seed.sh at ${seed}; skipping app floci seeding"
  fi
}

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

  declare -A HOSTS=(
    [gitea.dev.local]="$MGMT_IP"
    [argo.dev.local]="$DEV_IP"
    [grafana.dev.local]="$DEV_IP"
    [todo-app.dev.local]="$DEV_IP"
    [argo.prod.local]="$PROD_IP"
    [grafana.prod.local]="$PROD_IP"
    [todo-app.prod.local]="$PROD_IP"
  )

  if require_cmd dnsmasq && systemctl is-active --quiet systemd-resolved; then
    setup_dns_dnsmasq
  else
    warn "dnsmasq or systemd-resolved unavailable; relying on /etc/hosts only"
  fi
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

reconcile() {
  step "9b. Reconciling Argo CD applications (one-time)"
  for c in "${ARGO_CLUSTERS[@]}"; do
    nudge_until_healthy "$c" "root"
    nudge_until_healthy "$c"
  done
  log "All applications reconciled — the lab is ready to work."
}

nudge_until_healthy() {
  local c="$1" only="${2:-}"
  local label="${only:-all apps}"
  local deadline=$(( SECONDS + 480 ))
  log "[$c] reconciling ${label}..."
  while :; do
    local targets pending=0 total=0 app s h
    if [ -n "$only" ]; then
      targets="application.argoproj.io/${only}"
    else
      targets="$(kc "$c" -n argocd get applications.argoproj.io -o name 2>/dev/null || true)"
    fi
    while read -r app; do
      [ -z "$app" ] && continue
      total=$((total + 1))
      s="$(kc "$c" -n argocd get "$app" -o jsonpath='{.status.sync.status}'   2>/dev/null || true)"
      h="$(kc "$c" -n argocd get "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
      if [ "$s" != "Synced" ] || [ "$h" != "Healthy" ]; then
        pending=$((pending + 1))
        kc "$c" -n argocd annotate "$app" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
      fi
    done <<< "$targets"
    if [ "$total" -gt 0 ] && [ "$pending" -eq 0 ]; then
      log "[$c] ${label}: Synced & Healthy"
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      warn "[$c] ${label} not fully healthy within timeout; check 'task k8s:status'"
      kc "$c" -n argocd get applications.argoproj.io 2>/dev/null || true
      return 0
    fi
    sleep 10
  done
}

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

main() {
  log "Starting GitOps Enterprise Lab install"
  check_deps
  install_tools
  setup_aws_profile
  setup_floci
  seed_floci
  create_clusters
  detect_network
  install_metallb
  install_ingress
  install_gitea
  install_argocd
  build_and_load_image
  bootstrap_root
  setup_dns
  reconcile
  output
}

main "$@"
