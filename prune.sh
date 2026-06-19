#!/usr/bin/env bash
set -euo pipefail

#############################
# CONFIG
#############################

BINARIES=(
  "kubectl"
  "helm"
  "kind"
  "argocd"
  "k9s"
  "go"
)

HOSTS_ENTRIES=(
  "argocd.dev.local"
  "gitea.dev.local"
  "app.dev.local"
  "app.prod.local"
)

#############################
# LOGGING
#############################

log() { echo "[NUKE] $*"; }
fail() { echo "[❌ FAILED] $*" >&2; exit 1; }
ok() { echo "[✔] $*"; }

#############################
# CLEAN KIND (DOCKER SOURCE OF TRUTH)
#############################

delete_kind() {
  log "Deleting Kind containers..."

  sudo docker ps -a --format '{{.ID}} {{.Names}}' | while read -r id name; do
    if [[ "$name" == *"kind"* ]]; then
      sudo docker rm -f "$id" >/dev/null 2>&1 || true
    fi
  done

  sudo docker network prune -f >/dev/null 2>&1 || true
  sudo docker volume prune -f >/dev/null 2>&1 || true
}

#############################
# CLEAN KUBECONFIG
#############################

clean_kubeconfig() {
  log "Removing kubeconfig..."
  rm -rf "$HOME/.kube" || true
}

#############################
# REMOVE BINARIES (ALL SOURCES)
#############################

remove_binaries() {
  log "Removing binaries..."

  for bin in "${BINARIES[@]}"; do
    sudo rm -f "/usr/local/bin/$bin" || true
    sudo rm -f "/usr/bin/$bin" || true
    sudo rm -f "/snap/bin/$bin" || true
    rm -f "$HOME/.local/bin/$bin" || true
  done
}

#############################
# CLEAN HOSTS
#############################

clean_hosts() {
  log "Cleaning /etc/hosts..."
  for h in "${HOSTS_ENTRIES[@]}"; do
    sudo sed -i "/$h/d" /etc/hosts || true
  done
}

#############################
# GO CLEANUP
#############################

remove_go() {
  log "Removing Go..."

  sudo rm -rf /usr/local/go || true

  if [ -d "$HOME/go" ]; then
    sudo chown -R "$USER:$USER" "$HOME/go" || true
    sudo chmod -R u+rwX "$HOME/go" || true
    rm -rf "$HOME/go" || true
  fi
}

#############################
# K9s CLEANUP
#############################

remove_k9s() {
  log "Removing k9s..."

  sudo rm -f /usr/local/bin/k9s || true
  sudo rm -f /usr/bin/k9s || true
  sudo rm -f /snap/bin/k9s || true
  rm -rf "$HOME/.k9s" || true
  rm -rf "$HOME/.config/k9s" || true
}

#############################
# MISE CLEANUP
#############################

remove_mise() {
  log "Removing mise..."
  rm -rf "$HOME/.local/share/mise" || true
  rm -f "$HOME/.local/bin/mise" || true
}

#############################
# REAL VERIFICATION (IMPORTANT PART)
#############################

verify_uninstall() {
  log "Running REAL verification..."

  echo ""
  echo "=============================="
  echo "🔍 BINARY CHECK"
  echo "=============================="

  for bin in "${BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
      fail "$bin STILL EXISTS at $(command -v $bin)"
    else
      ok "$bin removed"
    fi
  done

  echo ""
  echo "=============================="
  echo "🔍 KIND / DOCKER CHECK"
  echo "=============================="

  if sudo docker ps -a --format '{{.Names}}' | grep -q "kind"; then
    fail "Kind containers STILL EXIST"
  else
    ok "No Kind containers found"
  fi

  echo ""
  echo "=============================="
  echo "🔍 KUBECONFIG CHECK"
  echo "=============================="

  if [ -d "$HOME/.kube" ]; then
    fail "Kubeconfig STILL EXISTS"
  else
    ok "Kubeconfig removed"
  fi

  echo ""
  echo "=============================="
  echo "🔍 GO CHECK"
  echo "=============================="

  if command -v go >/dev/null 2>&1; then
    fail "Go STILL INSTALLED"
  else
    ok "Go removed"
  fi

  echo ""
  echo "=============================="
  echo "🔍 K9s CHECK"
  echo "=============================="

  if command -v k9s >/dev/null 2>&1; then
    fail "k9s STILL INSTALLED"
  else
    ok "k9s removed"
  fi

  echo ""
  echo "=============================="
  echo "🎉 FINAL RESULT"
  echo "=============================="

  echo "✔ SYSTEM IS CLEAN"
}

#############################
# MAIN
#############################

main() {
  log "💣 FULL LAB PRUNE STARTING"

  delete_kind
  clean_kubeconfig
  clean_hosts
  remove_binaries
  remove_k9s
  remove_go
  remove_mise

  verify_uninstall
}

main