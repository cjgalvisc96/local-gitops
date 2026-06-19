#!/usr/bin/env bash
set -euo pipefail

log() { echo "[PRUNE] $*"; }

DEV_CLUSTER="local-dev"
PROD_CLUSTER="local-prod"

prune_clusters() {
  log "Deleting kind clusters..."
  kind delete cluster --name "$DEV_CLUSTER" || true
  kind delete cluster --name "$PROD_CLUSTER" || true
}

kill_ports() {
  log "Freeing ports..."
  sudo fuser -k 80/tcp || true
  sudo fuser -k 443/tcp || true
}

clean_docker() {
  log "Cleaning docker..."
  docker ps -aq | xargs -r docker rm -f || true
  docker system prune -af || true
}

clean_kube() {
  log "Removing kubeconfig..."
  rm -rf ~/.kube || true
}

clean_hosts() {
  log "Cleaning /etc/hosts..."
  sudo sed -i '/dev.local/d' /etc/hosts || true
}

remove_tools() {
  log "Removing installed tools..."
  sudo rm -f /usr/local/bin/kubectl || true
  sudo rm -f /usr/local/bin/kind || true
  sudo rm -f /usr/local/bin/k9s || true
  sudo rm -f /usr/local/bin/argocd || true
}

main() {
  prune_clusters
  kill_ports
  clean_docker
  clean_kube
  clean_hosts
  remove_tools
  log "DONE"
}

main