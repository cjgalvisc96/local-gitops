#!/usr/bin/env bash
set -euo pipefail

#############################
# VERSION CONSTANTS
#############################

K8S_VERSION="v1.36.1"

INGRESS_NGINX_VERSION="v1.11.2"

ARGO_CD_CHART_VERSION="7.7.0"
GITEA_CHART_VERSION="10.6.0"

MISE_INSTALL_URL="https://mise.run"

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
err() { echo "[ERROR] $*" >&2; exit 1; }

#############################
# HELPERS
#############################

get_kind_ip() {
  local cluster="$1"
  docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${cluster}-control-plane"
}

#############################
# OS DETECTION
#############################

detect_os() {
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)
      . /etc/os-release
      case "$ID" in
        debian|ubuntu) OS="debian" ;;
        arch) OS="arch" ;;
        fedora) OS="fedora" ;;
        *) err "Unsupported distro: $ID" ;;
      esac
      ;;
    *) err "Unsupported OS" ;;
  esac
}

#############################
# BASE INSTALL
#############################

install_base() {
  log "Installing base dependencies..."

  case "$OS" in
    debian)
      sudo apt update && sudo apt install -y curl git ca-certificates docker.io
      ;;
    arch)
      sudo pacman -Sy --noconfirm curl git ca-certificates docker
      ;;
    fedora)
      sudo dnf install -y curl git ca-certificates docker
      ;;
    macos)
      command -v brew >/dev/null || \
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      ;;
  esac
}

#############################
# MISE TOOLCHAIN
#############################

install_mise() {
  if command -v mise >/dev/null; then
    log "mise already installed"
    return
  fi

  log "Installing mise..."
  curl "$MISE_INSTALL_URL" | sh
  export PATH="$HOME/.local/bin:$PATH"
  eval "$(mise activate bash)"
}

install_toolchain() {
  log "Installing pinned toolchain..."

  if [ -f .mise.toml ]; then
    mise install
  else
    err ".mise.toml missing"
  fi
}

#############################
# CLUSTERS
#############################

create_clusters() {
  for CLUSTER in "$DEV_CLUSTER" "$PROD_CLUSTER"; do
    if ! kind get clusters | grep -q "^$CLUSTER$"; then
      log "Creating cluster $CLUSTER with Kubernetes ${K8S_VERSION}..."
      kind create cluster --name "$CLUSTER" --image "kindest/node:${K8S_VERSION}"
    else
      log "Cluster $CLUSTER already exists"
    fi
  done
}

#############################
# INGRESS
#############################

install_ingress() {
  for CLUSTER in "$DEV_CLUSTER" "$PROD_CLUSTER"; do
    log "Installing ingress on $CLUSTER..."
    kubectl config use-context "$CLUSTER"

    kubectl apply -f "$INGRESS_YAML_BASE"

    kubectl wait -n ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=180s || err "Ingress failed on $CLUSTER"
  done
}

#############################
# PLATFORM INSTALL
#############################

install_platform() {
  kubectl config use-context "$DEV_CLUSTER"

  kubectl create ns "$ARGO_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns "$GITEA_NS" --dry-run=client -o yaml | kubectl apply -f -

  log "Adding Helm repos..."
  helm repo add argo "$HELM_REPO_ARGO"
  helm repo add gitea "$HELM_REPO_GITEA"
  helm repo update

  log "Installing Argo CD (HTTP + NodePort)..."
  helm upgrade --install argocd argo/argo-argo-cd \
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

  log "Waiting for Argo CD..."
  kubectl wait -n "$ARGO_NS" \
    --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server \
    --timeout=180s || log "Argo CD still starting"
}

#############################
# REGISTER CLUSTERS
#############################

register_clusters() {
  log "Registering clusters with Argo CD..."

  kubectl config use-context "$DEV_CLUSTER"

  ARGO_IP=$(get_kind_ip "$DEV_CLUSTER")

  ARGO_NODEPORT=$(kubectl get svc argocd-server -n "$ARGO_NS" \
    -o jsonpath='{.spec.ports[0].nodePort}')

  ARGO_URL="http://${ARGO_IP}:${ARGO_NODEPORT}"

  log "Argo CD URL: $ARGO_URL"

  if argocd login "$ARGO_URL" \
    --username "$ARGO_GITEA_USER" \
    --password "$ARGO_GITEA_PASSWORD" \
    --insecure; then

    log "Registering dev cluster..."
    argocd cluster add "$DEV_CLUSTER" --yes || true

    log "Registering prod cluster..."
    argocd cluster add "$PROD_CLUSTER" --yes || true

  else
    err "Argo CD login failed"
  fi
}

#############################
# GITOPS
#############################

apply_gitops() {
  log "Applying GitOps manifests..."

  kubectl config use-context "$DEV_CLUSTER"

  kubectl apply -f applicationset.yaml || err "ApplicationSet failed"
  kubectl apply -f argocd-rbac.yaml || err "RBAC failed"
  kubectl apply -f rbac-k8s.yaml || err "K8s RBAC failed"

  sleep 5
  kubectl get applicationset -n "$ARGO_NS" || true
}

#############################
# DNS (LOCAL LAB)
#############################

setup_dns() {
  log "Setting up local DNS entries..."

  local hosts="127.0.0.1 argocd.dev.local gitea.dev.local app.dev.local app.prod.local"

  if ! grep -q "argocd.dev.local" /etc/hosts 2>/dev/null; then
    echo "$hosts" | sudo tee -a /etc/hosts >/dev/null || err "sudo required for /etc/hosts"
  fi
}

#############################
# MAIN
#############################

main() {
  log "🚀 Starting local GitOps platform bootstrap"

  detect_os
  install_base
  install_mise
  install_toolchain

  create_clusters
  install_ingress
  install_platform
  register_clusters
  apply_gitops
  setup_dns

  log ""
  log "✅ COMPLETE"
  log ""
  log "🌐 ACCESS:"
  log "  Argo CD:  http://<kind-node-ip>:<nodeport>"
  log "  Gitea:    http://gitea.dev.local"
  log "  Dev App:  http://app.dev.local"
  log "  Prod App: http://app.prod.local"
  log ""
  log "🔐 Credentials:"
  log "  User: $ARGO_GITEA_USER"
  log "  Pass: $ARGO_GITEA_PASSWORD"
  log ""
  log "💾 Clusters:"
  log "  Dev:  $DEV_CLUSTER"
  log "  Prod: $PROD_CLUSTER"
}

main