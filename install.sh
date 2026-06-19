#!/usr/bin/env bash
set -euo pipefail

DEV_CTX="kind-local-dev"
PROD_CTX="kind-local-prod"

log() { echo "[INFO] $*"; }

#############################
# TOOLING
#############################

install_tools() {
  log "Installing tools..."

  curl -sSL https://dl.k8s.io/release/v1.36.1/bin/linux/amd64/kubectl -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl

  curl -sSL https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 -o /tmp/kind
  sudo install -m 0755 /tmp/kind /usr/local/bin/kind

  curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  curl -sSL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz -o /tmp/k9s.tgz
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

  kind create cluster --name local-dev || true
  kind create cluster --name local-prod || true

  kubectl config use-context "$DEV_CTX"
}

wait_for_nodes() {
  log "Waiting for nodes..."
  kubectl wait --for=condition=Ready nodes --all --timeout=300s
}

#############################
# FIX TAINTS (SAFE)
#############################

fix_taints() {
  log "Removing control-plane taints (if any)..."

  for node in $(kubectl get nodes -o name); do
    kubectl taint "$node" node-role.kubernetes.io/control-plane- || true
    kubectl taint "$node" node-role.kubernetes.io/master- || true
  done

  log "Labeling nodes for ingress..."
  kubectl label nodes --all ingress-ready=true --overwrite || true
}

#############################
# HELM
#############################

setup_helm() {
  log "Setting Helm repos..."

  helm repo list | grep -q "^argo " || \
    helm repo add argo https://argoproj.github.io/argo-helm

  helm repo list | grep -q "^gitea " || \
    helm repo add gitea https://dl.gitea.com/charts

  helm repo update
}

#############################
# WAIT FOR DEPLOYMENT (FIXED BUG)
#############################

wait_for_rollout() {
  local deployment="$1"
  local ns="$2"

  kubectl rollout status deployment/"$deployment" -n "$ns" --timeout=300s
}

wait_for_webhook() {
  log "Waiting for ingress-nginx webhook..."

  for i in {1..60}; do
    kubectl get endpoints -n ingress-nginx ingress-nginx-controller-admission >/dev/null 2>&1 && return 0
    sleep 2
  done

  echo "[ERROR] ingress webhook not ready"
  exit 1
}

#############################
# INGRESS (CRITICAL ORDER)
#############################

install_ingress() {
  kubectl config use-context "$DEV_CTX"

  log "Installing ingress-nginx..."

  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/kind/deploy.yaml

  wait_for_rollout ingress-nginx-controller ingress-nginx
  wait_for_webhook
}

#############################
# METALLB
#############################

install_metallb() {
  kubectl config use-context "$DEV_CTX"

  log "Installing MetalLB..."

  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
}

#############################
# PLATFORM (ARGO + GITEA)
#############################

install_platform() {
  kubectl config use-context "$DEV_CTX"

  setup_helm

  log "Installing Argo CD..."
  helm upgrade --install argocd argo/argo-cd \
    -n argocd --create-namespace \
    -f argocd-values.yaml

  wait_for_rollout argocd-server argocd

  log "Installing Gitea..."
  helm upgrade --install gitea gitea/gitea \
    -n gitea --create-namespace \
    -f gitea-values.yaml

  wait_for_rollout gitea gitea
}

#############################
# GITOPS
#############################

apply_gitops() {
  kubectl config use-context "$DEV_CTX"

  kubectl apply -f argocd-rbac.yaml
  kubectl apply -f rbac-k8s.yaml
  kubectl apply -f applicationset.yaml
}

#############################
# OUTPUT
#############################

print_urls() {
  echo ""
  echo "======================================"
  echo "🚀 LOCAL GITOPS PLATFORM READY"
  echo "======================================"
  echo "Argo CD : http://argo.dev.local"
  echo "Gitea   : http://gitea.dev.local"
  echo "Dev App : http://app.dev.local"
  echo "Prod App: http://app.prod.local"
  echo "======================================"
}

#############################
# MAIN (STRICT ORDER = NO RACE CONDITIONS)
#############################

main() {
  log "🚀 STARTING STABLE BOOTSTRAP"

  install_tools

  create_clusters
  wait_for_nodes

  fix_taints

  install_ingress
  install_metallb

  install_platform

  apply_gitops

  print_urls
}

main