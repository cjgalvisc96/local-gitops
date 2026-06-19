#!/usr/bin/env bash
set -euo pipefail

DEV_CLUSTER="local-dev"
PROD_CLUSTER="local-prod"

log() { echo "[INSTALL] $*"; }

#############################
# INSTALL TOOLCHAIN (FULLY REPRODUCIBLE)
#############################

install_tools() {
  log "Installing tools..."

  # kubectl
  curl -sSL https://dl.k8s.io/release/v1.36.1/bin/linux/amd64/kubectl -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl

  # kind
  curl -sSL https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 -o /tmp/kind
  sudo install -m 0755 /tmp/kind /usr/local/bin/kind

  # helm
  curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  # k9s
  K9S_VER=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f4)
  curl -sSL "https://github.com/derailed/k9s/releases/download/${K9S_VER}/k9s_Linux_amd64.tar.gz" -o /tmp/k9s.tgz
  tar -xzf /tmp/k9s.tgz -C /tmp
  sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s

  # argocd CLI
  curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o /tmp/argocd
  sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
}

#############################
# CREATE CLUSTERS (ONLY IMPERATIVE PART LEFT)
#############################

create_clusters() {
  log "Creating kind clusters..."

  kind create cluster --name "$DEV_CLUSTER" --config clusters/dev.yaml || true
  kind create cluster --name "$PROD_CLUSTER" --config clusters/prod.yaml || true
}

#############################
# BOOTSTRAP PLATFORM (DECLARATIVE CORE)
#############################

bootstrap() {
  log "Switching to dev cluster..."
  kubectl config use-context "kind-$DEV_CLUSTER"

  log "Applying platform manifests..."
  kubectl apply -k bootstrap/

  log "Installing Argo CD control plane..."
  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
}

#############################
# OUTPUT
#############################

output() {
  echo ""
  echo "=================================="
  echo "🚀 PLATFORM READY"
  echo "=================================="
  echo "http://argo.dev.local"
  echo "http://gitea.dev.local"
  echo "http://app.dev.local"
  echo "http://app.prod.local"
  echo "=================================="
}

#############################
# MAIN
#############################

main() {
  log "🚀 FULL DECLARATIVE INSTALL START"

  install_tools
  create_clusters
  bootstrap
  output
}

main