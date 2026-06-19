#!/usr/bin/env bash
set -euo pipefail

DEV_CLUSTER="local-dev"
PROD_CLUSTER="local-prod"

ARGO_VERSION="v2.11.3"
METALLB_VERSION="v0.14.5"

log() { echo "[INSTALL] $*"; }

########################################
# TOOLS
########################################

install_tools() {
  log "Installing tools..."

  # kubectl
  curl -sSL https://dl.k8s.io/release/v1.36.1/bin/linux/amd64/kubectl -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl

  # kind
  curl -sSL https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 -o /tmp/kind
  sudo install -m 0755 /tmp/kind /usr/local/bin/kind

  # helm
  if ! command -v helm >/dev/null; then
    curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  # k9s
  K9S_VER=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f4)
  curl -sSL "https://github.com/derailed/k9s/releases/download/${K9S_VER}/k9s_Linux_amd64.tar.gz" -o /tmp/k9s.tgz
  tar -xzf /tmp/k9s.tgz -C /tmp
  sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s

  # argocd CLI
  curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o /tmp/argocd
  sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
}

########################################
# CLUSTERS (IDEMPOTENT)
########################################

create_clusters() {
  log "Creating clusters..."

  kind get clusters | grep -q "$DEV_CLUSTER" || \
    kind create cluster --name "$DEV_CLUSTER" --config clusters/dev.yaml

  kind get clusters | grep -q "$PROD_CLUSTER" || \
    kind create cluster --name "$PROD_CLUSTER" --config clusters/prod.yaml
}

########################################
# SWITCH CONTEXT
########################################

use_dev() {
  kubectl config use-context "kind-$DEV_CLUSTER"
}

########################################
# INGRES NGINX
########################################

install_ingress() {
  log "Installing ingress-nginx..."

  helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.hostPort.enabled=true \
    --wait
}

########################################
# ARGO CD (FIXED ORDER)
########################################

install_argocd() {
  log "Creating argocd namespace..."
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  log "Installing Argo CD ${ARGO_VERSION}..."
  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_VERSION}/manifests/install.yaml

  log "Waiting for Argo CD CRDs..."
  kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=180s || true
  kubectl wait --for=condition=Established crd/applicationsets.argoproj.io --timeout=180s || true
}

########################################
# METALLB (CRD FIRST)
########################################

install_metallb() {
  log "Installing MetalLB..."

  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml

  log "Waiting for MetalLB CRDs..."
  kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=180s || true
  kubectl wait --for=condition=Established crd/l2advertisements.metallb.io --timeout=180s || true

  log "Applying MetalLB config..."
  kubectl apply -f bootstrap/metallb/metallb-pool.yaml
}

########################################
# HELM APPS
########################################

install_apps() {
  log "Installing Gitea..."

  helm repo add gitea https://dl.gitea.com/charts || true
  helm repo update

  helm upgrade --install gitea gitea/gitea \
    -n gitea --create-namespace \
    -f bootstrap/gitea/values.yaml
}

########################################
# BOOTSTRAP KUSTOMIZE
########################################

apply_bootstrap() {
  log "Applying bootstrap manifests..."

  kubectl apply -k bootstrap/
}

########################################
# OUTPUT
########################################

output() {
  echo ""
  echo "=================================="
  echo "🚀 PLATFORM READY"
  echo "=================================="
  echo "Argo CD : http://argo.dev.local"
  echo "Gitea   : http://gitea.dev.local"
  echo "Dev App : http://app.dev.local"
  echo "Prod App: http://app.prod.local"
  echo "=================================="
}

########################################
# MAIN
########################################

main() {
  log "🚀 STARTING FULL BOOTSTRAP (FIXED ORDER)"

  install_tools
  create_clusters
  use_dev

  install_ingress
  install_argocd
  install_metallb
  install_apps

  apply_bootstrap

  output
}

main