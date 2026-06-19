#!/usr/bin/env bash
set -euo pipefail

DEV_CLUSTER="local-dev"
PROD_CLUSTER="local-prod"

METALLB_POOL="172.18.255.200-172.18.255.220"

log() { echo "[INSTALL] $*"; }

#############################
# TOOLS
#############################

install_tools() {
  log "Installing tools..."

  curl -sSL https://dl.k8s.io/release/v1.36.1/bin/linux/amd64/kubectl -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl

  curl -sSL https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 -o /tmp/kind
  sudo install -m 0755 /tmp/kind /usr/local/bin/kind

  curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  K9S_VER=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f4)
  curl -sSL "https://github.com/derailed/k9s/releases/download/${K9S_VER}/k9s_Linux_amd64.tar.gz" -o /tmp/k9s.tgz
  tar -xzf /tmp/k9s.tgz -C /tmp
  sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s

  curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o /tmp/argocd
  sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
}

#############################
# CLUSTERS
#############################

create_clusters() {
  log "Creating clusters..."

  kind create cluster --name "$DEV_CLUSTER" --config clusters/dev.yaml
  kind create cluster --name "$PROD_CLUSTER" --config clusters/prod.yaml
}

#############################
# WAIT UTIL
#############################

wait_ns() {
  NS=$1
  until kubectl get ns "$NS" >/dev/null 2>&1; do sleep 2; done
}

wait_rollout() {
  kubectl rollout status deployment -n "$1" --timeout=180s || true
}

#############################
# METALLB
#############################

install_metallb() {
  log "Installing MetalLB..."

  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

  kubectl wait --for=condition=available -n metallb-system deployment/controller --timeout=180s || true

  kubectl apply -f bootstrap/metallb/metallb-pool.yaml

  sleep 5
}

#############################
# INGRESS
#############################

install_ingress() {
  log "Installing ingress-nginx..."

  kubectl apply -f bootstrap/ingress-nginx.yaml

  kubectl wait -n ingress-nginx deployment/ingress-nginx-controller --timeout=180s || true
}

#############################
# PLATFORM
#############################

bootstrap() {
  kubectl config use-context "kind-$DEV_CLUSTER"

  kubectl apply -k bootstrap/

  install_metallb
  install_ingress

  log "Installing Argo CD..."
  kubectl create ns argocd || true
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  sleep 20

  kubectl apply -f bootstrap/argocd/argocd-rbac.yaml
  kubectl apply -f bootstrap/argocd/ingress.yaml

  log "Installing Gitea..."
  helm repo add gitea https://dl.gitea.com/charts || true
  helm repo update

  helm upgrade --install gitea gitea/gitea \
    -n gitea --create-namespace \
    -f bootstrap/gitea/values.yaml

  kubectl apply -f bootstrap/gitea/ingress.yaml

  log "Applying GitOps..."
  kubectl apply -f bootstrap/gitops/
}

#############################
# OUTPUT
#############################

output() {
  echo ""
  echo "=================================="
  echo "ARGO CD : http://argo.dev.local"
  echo "GITEA   : http://gitea.dev.local"
  echo "DEV APP : http://app.dev.local"
  echo "PROD APP: http://app.prod.local"
  echo "=================================="
}

main() {
  install_tools
  create_clusters
  bootstrap
  output
}

main