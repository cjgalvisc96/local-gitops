#!/usr/bin/env bash
set -euo pipefail

log() { echo "[PRUNE] $*"; }

DEV_CLUSTER="local-dev"
PROD_CLUSTER="local-prod"

HOSTS=("argo.dev.local" "gitea.dev.local" "app.dev.local" "app.prod.local")

#############################
# STOP SYSTEM SERVICES
#############################

stop_services() {
  log "Stopping conflicting services..."
  sudo fuser -k 80/tcp || true
  sudo fuser -k 443/tcp || true
  sudo systemctl stop apache2 || true
  sudo systemctl stop nginx || true
}

#############################
# DELETE KIND CLUSTERS
#############################

delete_clusters() {
  log "Deleting kind clusters..."

  kind delete cluster --name "$DEV_CLUSTER" || true
  kind delete cluster --name "$PROD_CLUSTER" || true
}

#############################
# CLEAN DOCKER
#############################

cleanup_docker() {
  log "Cleaning docker..."

  docker ps -a --format '{{.Names}}' | grep kind | xargs -r docker rm -f || true
  docker network ls --format '{{.Name}}' | grep kind | xargs -r docker network rm || true
}

#############################
# CLEAN KUBECONFIG
#############################

clean_kubeconfig() {
  log "Removing kubeconfig..."
  rm -rf ~/.kube || true
}

#############################
# CLEAN /etc/hosts
#############################

clean_hosts() {
  log "Cleaning hosts..."

  for h in "${HOSTS[@]}"; do
    sudo sed -i "/$h/d" /etc/hosts || true
  done
}

#############################
# REMOVE TOOLCHAIN
#############################

remove_tools() {
  log "Removing installed tools..."

  sudo rm -f /usr/local/bin/kubectl || true
  sudo rm -f /usr/local/bin/kind || true
  sudo rm -f /usr/local/bin/helm || true
  sudo rm -f /usr/local/bin/argocd || true
  sudo rm -f /usr/local/bin/k9s || true
}

#############################
# VERIFY CLEAN STATE
#############################

verify() {
  log "Verifying cleanup..."

  command -v kubectl >/dev/null && echo "[WARN] kubectl still exists" || echo "[OK] kubectl removed"
  command -v kind >/dev/null && echo "[WARN] kind still exists" || echo "[OK] kind removed"
  command -v helm >/dev/null && echo "[WARN] helm still exists" || echo "[OK] helm removed"
}

#############################
# MAIN
#############################

main() {
  log "💣 FULL PLATFORM PRUNE START"

  stop_services
  delete_clusters
  cleanup_docker
  clean_kubeconfig
  clean_hosts
  remove_tools

  verify

  log "✔ PRUNE COMPLETE"
}

main