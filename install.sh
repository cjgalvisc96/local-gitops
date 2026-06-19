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
NGINX_NS="ingress-nginx"
DEV_APP_NS="dev-app"
PROD_APP_NS="prod-app"

ARGO_GITEA_USER="admin"
ARGO_GITEA_PASSWORD="adminadmin1"

INGRESS_YAML="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

#############################
# LOGGING
#############################

log() { echo "[INFO] $*"; }

#############################
# HOST IP (CRITICAL FIX)
#############################

get_host_ip() {
  ip route get 1.1.1.1 | awk '{print $7; exit}'
}

#############################
# TOOLING (ASSUMED GLOBAL OK)
#############################

install_tools() {
  log "Installing kubectl..."
  curl -sSL "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl

  log "Installing kind..."
  curl -sSL https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 -o /tmp/kind
  sudo install -m 0755 /tmp/kind /usr/local/bin/kind

  log "Installing helm..."
  curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  log "Installing argocd CLI..."
  curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o /tmp/argocd
  sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd

  log "Installing k9s..."
  K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f4)
  curl -sSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -o /tmp/k9s.tgz
  tar -xzf /tmp/k9s.tgz -C /tmp
  sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s
}

#############################
# CLUSTERS
#############################

create_clusters() {
  for c in "$DEV_CLUSTER" "$PROD_CLUSTER"; do
    kind get clusters | grep -q "$c" || \
      kind create cluster --name "$c" --image "kindest/node:${K8S_VERSION}"
  done
}

#############################
# INGRESS
#############################

install_ingress() {
  for c in "$DEV_CLUSTER" "$PROD_CLUSTER"; do
    kubectl config use-context "kind-$c"

    kubectl apply -f "$INGRESS_YAML"

    kubectl wait -n ingress-nginx \
      --for=condition=available deployment/ingress-nginx-controller \
      --timeout=300s || true

    kubectl delete validatingwebhookconfiguration ingress-nginx-admission || true
  done
}

#############################
# NAMESPACES (FIXED)
#############################

create_namespaces() {
  kubectl config use-context "kind-$DEV_CLUSTER"

  kubectl create ns "$ARGO_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns "$GITEA_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns "$NGINX_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns "$DEV_APP_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns "$PROD_APP_NS" --dry-run=client -o yaml | kubectl apply -f -
}

#############################
# HELM
#############################

setup_helm() {
  helm repo list | grep -q argo || helm repo add argo "$HELM_REPO_ARGO"
  helm repo list | grep -q gitea || helm repo add gitea "$HELM_REPO_GITEA"
  helm repo update
}

#############################
# PLATFORM
#############################

install_platform() {
  kubectl config use-context "kind-$DEV_CLUSTER"

  setup_helm

  log "Installing Argo CD..."
  helm upgrade --install argocd argo/argo-cd \
    -n "$ARGO_NS" \
    --version "$ARGO_CD_CHART_VERSION" \
    -f argocd-values.yaml

  log "Installing Gitea..."
  helm upgrade --install gitea gitea/gitea \
    -n "$GITEA_NS" \
    --version "$GITEA_CHART_VERSION" \
    -f gitea-values.yaml
}

#############################
# DNS FIX (CRITICAL)
#############################

setup_dns() {
  local ip
  ip=$(get_host_ip)

  log "Updating /etc/hosts -> $ip"

  sudo sed -i '/argo.dev.local/d' /etc/hosts || true
  sudo sed -i '/gitea.dev.local/d' /etc/hosts || true
  sudo sed -i '/app.dev.local/d' /etc/hosts || true
  sudo sed -i '/app.prod.local/d' /etc/hosts || true

  echo "$ip argo.dev.local gitea.dev.local app.dev.local app.prod.local" | sudo tee -a /etc/hosts >/dev/null
}

#############################
# VERIFY
#############################

verify() {
  log "Cluster status:"
  kubectl get nodes -A || true

  log "Namespaces:"
  kubectl get ns

  log "Ingress:"
  kubectl get ingress -A || true
}

#############################
# MAIN
#############################

main() {
  log "🚀 FULL CLEAN INSTALL"

  install_tools
  create_clusters
  install_ingress
  create_namespaces
  install_platform
  setup_dns
  verify

  local ip
  ip=$(get_host_ip)

  echo ""
  log "🌐 ACCESS URLS"
  echo "--------------------------------"
  echo "Argo CD : http://argo.dev.local"
  echo "Gitea   : http://gitea.dev.local"
  echo "Dev App : http://app.dev.local"
  echo "Prod App: http://app.prod.local"
  echo "--------------------------------"
  echo "Host IP: $ip"
}

main