#!/usr/bin/env bash
set -euo pipefail

#############################
# VERSION CONSTANTS
#############################

K8S_VERSION="v1.36.1"
INGRESS_NGINX_VERSION="v1.11.2"

ARGO_CD_CHART_VERSION="7.7.0"
GITEA_CHART_VERSION="10.6.0"

HELM_REPO_ARGO="https://argoproj.github.io/argo-helm"
HELM_REPO_GITEA="https://dl.gitea.com/charts"

#############################
# CLUSTERS
#############################

DEV_CLUSTER="kind-local-dev"
PROD_CLUSTER="kind-local-prod"

ARGO_NS="argocd"
GITEA_NS="gitea"

ARGO_GITEA_USER="admin"
ARGO_GITEA_PASSWORD="adminadmin1"

INGRESS_YAML_BASE="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

#############################
# LOGGING
#############################

log() { echo "[INFO] $*"; }

#############################
# TEMP HELPERS (NO LOCAL FILES)
#############################

safe_download() {
  curl -sSL "$1" -o "/tmp/$2"
}

safe_install_bin() {
  sudo install -m 0755 "/tmp/$1" "/usr/local/bin/$2"
  rm -f "/tmp/$1"
}

#############################
# GLOBAL TOOLCHAIN
#############################

install_tools_global() {

  log "Installing global Kubernetes toolchain..."

  # kubectl
  if ! command -v kubectl >/dev/null; then
    log "Installing kubectl..."
    safe_download "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" "kubectl"
    safe_install_bin "kubectl" "kubectl"
  fi

  # kind
  if ! command -v kind >/dev/null; then
    log "Installing kind..."
    safe_download "https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64" "kind"
    safe_install_bin "kind" "kind"
  fi

  # helm
  if ! command -v helm >/dev/null; then
    log "Installing helm..."
    curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  # argocd CLI
  if ! command -v argocd >/dev/null; then
    log "Installing argocd CLI..."
    safe_download "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64" "argocd"
    safe_install_bin "argocd" "argocd"
  fi

  # k9s
  if ! command -v k9s >/dev/null; then
    log "Installing k9s..."
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f4)

    safe_download \
      "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" \
      "k9s.tar.gz"

    tar -xzf /tmp/k9s.tar.gz -C /tmp
    sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s
    rm -f /tmp/k9s /tmp/k9s.tar.gz
  fi
}

#############################
# CLUSTERS
#############################

create_cluster() {
  local name="$1"

  if kind get clusters | grep -q "^$name$"; then
    log "Cluster $name already exists"
  else
    log "Creating cluster $name..."
    kind create cluster --name "$name" --image "kindest/node:${K8S_VERSION}"
  fi
}

create_clusters() {
  create_cluster "$DEV_CLUSTER"
  create_cluster "$PROD_CLUSTER"
}

#############################
# INGRESS (FIXED)
#############################

install_ingress() {
  for CLUSTER in "$DEV_CLUSTER" "$PROD_CLUSTER"; do
    log "Installing ingress on $CLUSTER..."

    kubectl config use-context "kind-$CLUSTER"
    kubectl apply -f "$INGRESS_YAML_BASE"

    kubectl wait -n ingress-nginx \
      --for=condition=available deployment/ingress-nginx-controller \
      --timeout=300s || true

    # 🔥 IMPORTANT FIX FOR LOCAL LABS
    kubectl delete validatingwebhookconfiguration ingress-nginx-admission || true

    sleep 15
  done
}

#############################
# HELM SETUP
#############################

setup_helm_repos() {
  helm repo list | grep -q "^argo" || helm repo add argo "$HELM_REPO_ARGO"
  helm repo list | grep -q "^gitea" || helm repo add gitea "$HELM_REPO_GITEA"
  helm repo update
}

#############################
# PLATFORM
#############################

install_platform() {
  kubectl config use-context "kind-$DEV_CLUSTER"

  kubectl create ns "$ARGO_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns "$GITEA_NS" --dry-run=client -o yaml | kubectl apply -f -

  setup_helm_repos

  log "Installing Argo CD..."
  helm upgrade --install argocd argo/argo-cd \
    -n "$ARGO_NS" \
    --version "$ARGO_CD_CHART_VERSION" \
    -f argocd-values.yaml \
    --set server.service.type=NodePort \
    --set server.extraArgs="{--insecure}" \
    --set configs.params."server\.insecure"=true

  log "Installing Gitea..."
  helm upgrade --install gitea gitea/gitea \
    -n "$GITEA_NS" \
    --version "$GITEA_CHART_VERSION" \
    -f gitea-values.yaml
}

#############################
# NETWORK HELPERS
#############################

get_kind_ip() {
  docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1-control-plane"
}

get_nodeport() {
  kubectl get svc argocd-server -n "$ARGO_NS" \
    -o jsonpath='{.spec.ports[0].nodePort}'
}

#############################
# REGISTER CLUSTERS
#############################

register_clusters() {
  kubectl config use-context "kind-$DEV_CLUSTER"

  ARGO_IP=$(get_kind_ip "$DEV_CLUSTER")
  ARGO_PORT=$(get_nodeport)

  ARGO_URL="http://${ARGO_IP}:${ARGO_PORT}"

  log "Argo CD URL: $ARGO_URL"

  argocd login "$ARGO_URL" \
    --username "$ARGO_GITEA_USER" \
    --password "$ARGO_GITEA_PASSWORD" \
    --insecure || true

  argocd cluster add "kind-$DEV_CLUSTER" --yes || true
  argocd cluster add "kind-$PROD_CLUSTER" --yes || true
}

#############################
# GITOPS
#############################

apply_gitops() {
  kubectl config use-context "kind-$DEV_CLUSTER"

  kubectl apply -f applicationset.yaml || true
  kubectl apply -f argocd-rbac.yaml || true
  kubectl apply -f rbac-k8s.yaml || true
}

#############################
# DNS
#############################

setup_dns() {
  local hosts="127.0.0.1 argocd.dev.local gitea.dev.local app.dev.local app.prod.local"

  grep -q "argocd.dev.local" /etc/hosts 2>/dev/null || \
    echo "$hosts" | sudo tee -a /etc/hosts >/dev/null
}

#############################
# FINAL OUTPUT
#############################

print_urls() {
  local ip
  ip=$(get_kind_ip "$DEV_CLUSTER")

  local port
  port=$(get_nodeport)

  echo ""
  log "🌐 ACCESS URLS"
  echo "----------------------------------"
  log "Argo CD:  http://${ip}:${port}"
  log "Gitea:    http://gitea.dev.local"
  log "Dev App:  http://app.dev.local"
  log "Prod App: http://app.prod.local"
  echo "----------------------------------"
  echo ""

  log "🔐 Credentials"
  log "User: $ARGO_GITEA_USER"
  log "Pass: $ARGO_GITEA_PASSWORD"
}

#############################
# MAIN
#############################

main() {
  log "🚀 Starting full GitOps platform bootstrap"

  install_tools_global
  create_clusters
  install_ingress
  install_platform
  register_clusters
  apply_gitops
  setup_dns

  print_urls

  log "✅ COMPLETE"
}

main