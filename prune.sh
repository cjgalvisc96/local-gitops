#!/usr/bin/env bash
set -euo pipefail

log() { echo "[NUKE] $*"; }

HOSTS=("argo.dev.local" "gitea.dev.local" "app.dev.local" "app.prod.local")

#############################
# STOP PORT CONFLICTS
#############################

stop_ports() {
  log "Stopping port conflicts..."

  sudo fuser -k 80/tcp || true
  sudo fuser -k 443/tcp || true

  sudo systemctl stop apache2 || true
  sudo systemctl stop nginx || true
}

#############################
# DELETE KIND PROPERLY
#############################

delete_kind() {
  log "Deleting Kind clusters (CLI)..."

  kind delete cluster --name local-dev || true
  kind delete cluster --name local-prod || true
}

#############################
# FORCE CLEAN DOCKER (CRITICAL FIX)
#############################

cleanup_docker() {
  log "Removing Kind containers..."

  docker ps -a --format '{{.ID}} {{.Names}}' \
    | grep kind \
    | awk '{print $1}' \
    | xargs -r docker rm -f || true

  log "Removing Kind networks..."

  # ONLY remove kind networks AFTER containers are gone
  docker network ls --format '{{.Name}}' \
    | grep kind \
    | xargs -r docker network rm || true
}

#############################
# CLEAN KUBECONFIG
#############################

clean_kubeconfig() {
  log "Cleaning kubeconfig..."
  rm -rf ~/.kube || true
}

#############################
# CLEAN HOSTS
#############################

clean_hosts() {
  log "Cleaning /etc/hosts..."

  for h in "${HOSTS[@]}"; do
    sudo sed -i "/$h/d" /etc/hosts || true
  done
}

#############################
# MAIN
#############################

main() {
  log "💣 FULL PRUNE START"

  stop_ports
  delete_kind
  cleanup_docker   # 🔥 FIXED ORDER
  clean_kubeconfig
  clean_hosts

  log "✔ PRUNE COMPLETE"
}

main