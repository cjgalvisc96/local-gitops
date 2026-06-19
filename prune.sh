#!/usr/bin/env bash
set -euo pipefail

#############################
# CONFIG
#############################

DEV_CLUSTER="kind-local-dev"
PROD_CLUSTER="kind-local-prod"

HOSTS_ENTRIES=(
  "argocd.dev.local"
  "gitea.dev.local"
  "app.dev.local"
  "app.prod.local"
)

BINARIES=(
  "kubectl"
  "helm"
  "kind"
  "argocd"
)

#############################
# LOGGING
#############################

log() { echo "[NUKE] $*"; }
warn() { echo "[WARN] $*"; }

#############################
# DELETE KIND CLUSTERS
#############################

delete_clusters() {
  log "Deleting Kind clusters..."

  for c in "$DEV_CLUSTER" "$PROD_CLUSTER"; do
    if kind get clusters 2>/dev/null | grep -q "^$c$"; then
      kind delete cluster --name "$c" || true
      log "Deleted cluster $c"
    fi
  done
}

#############################
# CLEAN DOCKER
#############################

clean_docker() {
  log "Cleaning Docker leftovers..."

  docker ps -a --format '{{.ID}} {{.Names}}' | while read -r id name; do
    if [[ "$name" == *"kind"* ]]; then
      docker rm -f "$id" >/dev/null 2>&1 || true
      log "Removed container $name"
    fi
  done

  docker network prune -f >/dev/null 2>&1 || true
}

#############################
# CLEAN KUBECTL CONTEXTS
#############################

clean_kubectl() {
  log "Cleaning kubectl contexts..."

  for c in "$DEV_CLUSTER" "$PROD_CLUSTER"; do
    kubectl config delete-context "$c" >/dev/null 2>&1 || true
    kubectl config delete-cluster "$c" >/dev/null 2>&1 || true
  done
}

#############################
# REMOVE /etc/hosts ENTRIES
#############################

clean_hosts() {
  log "Cleaning /etc/hosts..."

  for h in "${HOSTS_ENTRIES[@]}"; do
    sudo sed -i "/$h/d" /etc/hosts || true
  done
}

#############################
# REMOVE BINARIES
#############################

remove_binaries() {
  log "Removing Kubernetes toolchain binaries..."

  for bin in "${BINARIES[@]}"; do
    for path in \
      "$HOME/.local/bin/$bin" \
      "/usr/local/bin/$bin" \
      "/usr/bin/$bin"
    do
      if [ -f "$path" ]; then
        sudo rm -f "$path" || rm -f "$path" || true
        log "Removed $path"
      fi
    done
  done
}

#############################
# REMOVE GO
#############################

remove_go() {
  log "Removing Go installation..."

  # common install locations
  sudo rm -rf /usr/local/go || true
  rm -rf "$HOME/go" || true

  # remove PATH entries from shell configs
  for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$f" ]; then
      sed -i '/go\/bin/d' "$f" || true
      sed -i '/GOROOT/d' "$f" || true
      sed -i '/GOPATH/d' "$f" || true
      log "Cleaned Go env from $f"
    fi
  done
}

#############################
# CLEAN MISE (OPTIONAL BUT SAFE)
#############################

remove_mise() {
  log "Removing mise..."

  rm -rf "$HOME/.local/share/mise" || true
  rm -f "$HOME/.local/bin/mise" || true

  for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
    sed -i '/mise/d' "$f" || true
  done
}

#############################
# MAIN
#############################

main() {
  log "💣 Starting FULL lab teardown"

  delete_clusters
  clean_docker
  clean_kubectl
  clean_hosts
  remove_binaries
  remove_go
  remove_mise

  log ""
  log "✅ COMPLETE WIPE FINISHED"
  log ""
  log "Verify:"
  log "  kind get clusters"
  log "  kubectl version"
  log "  helm version"
  log "  argocd version"
  log "  go version"
  log "  docker ps -a"
}

main