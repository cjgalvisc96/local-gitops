#!/usr/bin/env bash
set -euo pipefail

#############################
# CONFIG
#############################

KIND_CLUSTER_NAME="dev"
ARGO_NAMESPACE="argocd"
GITEA_NAMESPACE="gitea"
ARGO_VALUES="argocd-values.yaml"
GITEA_VALUES="gitea-values.yaml"
USERNAME="admin"
ARGO_PASSWORD="adminadmin1"

#############################
# LOGGING
#############################

log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

#############################
# PREREQS
#############################

check_prereqs() {
  log "Checking prerequisites..."

  for c in go docker kubectl helm argocd; do
    command -v "$c" >/dev/null || err "$c is not installed"
  done
}

#############################
# KIND
#############################

install_kind() {
  log "Installing kind..."
  go install sigs.k8s.io/kind@v0.32.0
}

create_cluster() {
  log "Creating kind cluster..."

  if kind get clusters | grep -q "$KIND_CLUSTER_NAME"; then
    log "Cluster already exists, skipping"
    return
  fi

  kind create cluster --name "$KIND_CLUSTER_NAME"
  kubectl config use-context "kind-$KIND_CLUSTER_NAME"
}

#############################
# ARGO CD
#############################

install_argocd() {
  log "Installing Argo CD..."

  kubectl create namespace "$ARGO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
  helm repo update >/dev/null

  helm upgrade --install argocd argo/argo-cd \
    -n "$ARGO_NAMESPACE" \
    -f "$ARGO_VALUES"
}

#############################
# GITEA
#############################

install_gitea() {
  log "Installing Gitea..."

  kubectl create namespace "$GITEA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  helm repo add gitea-charts https://dl.gitea.com/charts/ >/dev/null
  helm repo update >/dev/null

  helm upgrade --install gitea gitea-charts/gitea \
    -n "$GITEA_NAMESPACE" \
    -f "$GITEA_VALUES"
}

#############################
# CLUSTER INFO
#############################

get_ip() {
  docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    "${KIND_CLUSTER_NAME}-control-plane"
}

#############################
# ARGO LOGIN + APP
#############################

argocd_bootstrap() {
  local ip="$1"

  log "Logging into Argo CD..."

  argocd login "$ip:30080" \
    --username "$USERNAME" \
    --password "$ARGO_PASSWORD" \
    --insecure || true

  log "Adding repo..."

  argocd repo add \
    http://gitea-http.gitea.svc.cluster.local:3000/$USERNAME/local-nginx.git \
    --username "$USERNAME" \
    --password "$ARGO_PASSWORD" || true

  log "Creating app..."

  argocd app create nginx-app \
    --repo http://gitea-http.gitea.svc.cluster.local:3000/$USERNAME/local-nginx.git \
    --path nginx \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace local-nginx || true

  argocd app sync nginx-app || true
}

#############################
# MAIN
#############################

main() {
  log "🚀 Starting full Kind + GitOps setup"

  check_prereqs
  install_kind
  create_cluster

  install_argocd
  install_gitea

  IP=$(get_ip)
  log "Cluster IP: $IP"

  argocd_bootstrap "$IP"

  log "✅ DONE - Everything is installed"
  log "Argo CD: http://$IP:30080"
  log "Gitea:  http://$IP:30030"
}

main