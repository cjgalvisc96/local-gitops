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

  for repo in "${GITEA_REPOS[@]}"; do
    curl -sf -u "$auth" -X POST "${base}/api/v1/orgs/${GITEA_ORG}/repos" \
      -H 'Content-Type: application/json' \
      -d "{\"name\":\"${repo}\",\"private\":false,\"auto_init\":false}" >/dev/null 2>&1 || true
    push_repo "$repo" "${base}"
  done
  kill "$pf" >/dev/null 2>&1 || true
  trap - RETURN
}

# push_repo <local-dir-name> <gitea-base-url>
push_repo() {
  local repo="$1" base="$2"
  local src="${REPO_ROOT}/${repo}"
  [ -d "$src" ] || { warn "missing source dir for repo '$repo'"; return; }
  log "pushing '$repo' to Gitea"
  local tmp; tmp="$(mktemp -d)"
  cp -r "$src/." "$tmp/"
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

# -----------------------------------------------------------------------------
# 6. Install Argo CD (management)
# -----------------------------------------------------------------------------
install_argocd() {
  step "6. Installing Argo CD on the management cluster"
  kc "$MGMT_CLUSTER" create namespace argocd --dry-run=client -o yaml | kc "$MGMT_CLUSTER" apply -f -
  kc "$MGMT_CLUSTER" apply -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
  log "applying Argo CD config (insecure server, RBAC, ingress)"
  kc "$MGMT_CLUSTER" apply -f bootstrap/argocd/argocd-cmd-params.yaml
  kc "$MGMT_CLUSTER" apply -f bootstrap/argocd/argocd-rbac.yaml
  kc "$MGMT_CLUSTER" apply -f bootstrap/argocd/ingress.yaml
  log "waiting for Argo CD to become ready"
  kc "$MGMT_CLUSTER" wait --for=condition=Established crd/applications.argoproj.io --timeout=180s
  kc "$MGMT_CLUSTER" wait --for=condition=Established crd/applicationsets.argoproj.io --timeout=180s
  kc "$MGMT_CLUSTER" -n argocd rollout restart deploy/argocd-server
  kc "$MGMT_CLUSTER" -n argocd rollout status deploy/argocd-server --timeout=300s
}

# -----------------------------------------------------------------------------
# 7 & 8. Register dev / prod clusters with Argo CD
# -----------------------------------------------------------------------------
# register_cluster <cluster-name>
register_cluster() {
  local c="$1"
  step "Registering '$c' cluster with Argo CD"
  local ip; ip="$(cluster_internal_ip "$c")"
  [ -n "$ip" ] || die "could not determine internal IP of $c-control-plane"
  local server="https://${ip}:6443"

  local kcfg; kcfg="$(mktemp)"
  kind get kubeconfig --name "$c" >"$kcfg"
  local ca cert key
  ca="$(kubectl --kubeconfig="$kcfg" config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  cert="$(kubectl --kubeconfig="$kcfg" config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')"
  key="$(kubectl --kubeconfig="$kcfg" config view --raw -o jsonpath='{.users[0].user.client-key-data}')"
  rm -f "$kcfg"

  log "[$c] internal API endpoint: $server"
  kc "$MGMT_CLUSTER" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${c}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: ${c}
type: Opaque
stringData:
  name: ${c}
  server: ${server}
  config: |
    {"tlsClientConfig":{"caData":"${ca}","certData":"${cert}","keyData":"${key}"}}
EOF
}

# -----------------------------------------------------------------------------
# 9. Bootstrap the root Application (app-of-apps)
# -----------------------------------------------------------------------------
bootstrap_root() {
  step "9. Bootstrapping the root Application"
  kc "$MGMT_CLUSTER" apply -f bootstrap/argocd/root-app.yaml
  log "Argo CD will now reconcile platform-config -> projects, applicationsets, apps."
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

  # SSM Parameter Store values consumed by the ExternalSecrets in each env.
  for env in dev prod; do
    aws --endpoint-url "$ep" ssm put-parameter --overwrite \
      --name "/gitops/${env}/app1/greeting" --type String \
      --value "hello from ${env} (via floci SSM)" >/dev/null 2>&1 \
      && log "ssm: /gitops/${env}/app1/greeting" || warn "failed to put SSM param for ${env}"
  done

  # ECR registry/repos (the lab's "docker images register using AWS ECR").
  for repo in app1 app2; do
    aws --endpoint-url "$ep" ecr create-repository --repository-name "gitops/${repo}" \
      >/dev/null 2>&1 && log "ecr: gitops/${repo}" || true
  done
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

  # Host -> IP map. Management UIs are aliased under the *.dev/*.prod names.
  declare -A HOSTS=(
    [gitea.dev.local]="$MGMT_IP"
    [argo.dev.local]="$MGMT_IP"
    [argo.prod.local]="$MGMT_IP"
    [grafana.dev.local]="$DEV_IP"
    [app1.dev.local]="$DEV_IP"
    [app2.dev.local]="$DEV_IP"
    [grafana.prod.local]="$PROD_IP"
    [app1.prod.local]="$PROD_IP"
    [app2.prod.local]="$PROD_IP"
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
  step "10. Platform ready"
  local argo_pw; argo_pw="$(kc "$MGMT_CLUSTER" -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  cat <<EOF

==================================================================
  🚀  GitOps Enterprise Lab is UP
==================================================================
  Control plane (management cluster)
    Gitea        http://gitea.dev.local        ($GITEA_ADMIN_USER / $GITEA_ADMIN_PASSWORD)
    Argo CD      http://argo.dev.local          (admin / ${argo_pw:-<see below>})
                 http://argo.prod.local
  DEV cluster
    Grafana      http://grafana.dev.local       (anonymous viewer / admin:admin)
    app1         http://app1.dev.local
    app2         http://app2.dev.local
  PROD cluster
    Grafana      http://grafana.prod.local
    app1         http://app1.prod.local
    app2         http://app2.prod.local
------------------------------------------------------------------
  Argo CD admin password:
    kubectl --context kind-management -n argocd get secret \\
      argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  Watch sync:  argocd app list   (after: argocd login argo.dev.local)
  Tip:         k9s --context kind-management
==================================================================
EOF
}

# -----------------------------------------------------------------------------
main() {
  log "Starting GitOps Enterprise Lab install"
  check_deps          # 0
  install_tools       # 1
  setup_aws_profile   # local AWS 'floci' profile in ~/.aws
  setup_floci         # local AWS (floci) — start before workloads need it
  seed_floci          # SSM params + ECR repos
  create_clusters     # 2
  install_metallb     # 3
  install_ingress     # 4
  install_gitea       # 5 (+ seed repos)
  install_argocd      # 6
  register_cluster "$DEV_CLUSTER"   # 7
  register_cluster "$PROD_CLUSTER"  # 8
  bootstrap_root      # 9
  setup_dns           # 10a
  output              # 10b
}

main "$@"
