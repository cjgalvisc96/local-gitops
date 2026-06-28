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
  step "3. Installing MetalLB on the management cluster"
  for c in "${CLUSTERS[@]}"; do
    log "[$c] applying MetalLB ${METALLB_VERSION}"
    kc "$c" apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"
    kc "$c" wait --for=condition=Available deploy/controller -n metallb-system --timeout=180s
    kc "$c" wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=120s
    log "[$c] configuring address pool ${MGMT_POOL}"
    kc "$c" apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: pool
  namespace: metallb-system
spec:
  addresses:
    - ${MGMT_POOL}
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
  log "ingress IPs  mgmt=$MGMT_IP  eks-dev=$EKS_DEV_IP  eks-prod=$EKS_PROD_IP"

  declare -A HOSTS=(
    [gitea.dev.local]="$MGMT_IP"
    [grafana.dev.local]="$EKS_DEV_IP"
    [grafana.prod.local]="$EKS_PROD_IP"
    [argo.dev.local]="$EKS_DEV_IP"
    [argo.prod.local]="$EKS_PROD_IP"
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

output() {
  step "Management plane ready (kind / Gitea)"
  cat <<EOF

  Gitea   http://gitea.dev.local   ($GITEA_ADMIN_USER / $GITEA_ADMIN_PASSWORD)

  Next: bootstrapping the floci-EKS clusters (Argo CD + observability)...
EOF
}

main() {
  log "Starting GitOps Enterprise Lab install (Kubernetes layer)"
  check_deps
  install_tools
  setup_aws_profile
  if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "kind-${MGMT_CLUSTER}"; then
    die "kind-${MGMT_CLUSTER} context not found — provision the infra first (task install applies Terragrunt + exports the kubeconfig)"
  fi
  detect_network
  install_metallb
  install_ingress
  install_gitea
  setup_dns
  output
}

if [ "${SYNC_ONLY:-false}" = "true" ]; then
  log "SYNC_ONLY=true — re-pushing GitOps repos to Gitea (no cluster/Argo rebuild)"
  detect_network
  seed_gitea
  log "pushed; Argo reconciles on its next poll (force now with: task k8s:sync ENV=dev)"
  exit 0
fi

main "$@"
