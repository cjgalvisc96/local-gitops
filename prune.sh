#!/usr/bin/env bash
# =============================================================================
# Tear down everything install.sh created: kind clusters and their Docker
# footprint (containers, volumes, the kind network, the node image), local DNS,
# kube contexts, and (optionally) the installed CLI tools.
#
#   ./prune.sh            # remove clusters + Docker artifacts + DNS + contexts
#   ./prune.sh --tools    # also remove kubectl/kind/k9s/argocd binaries
# =============================================================================
set -uo pipefail   # not -e: prune must continue past missing pieces

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
source lib/common.sh

REMOVE_TOOLS=0
[ "${1:-}" = "--tools" ] && REMOVE_TOOLS=1

prune_clusters() {
  step "Deleting kind clusters"
  for c in "${CLUSTERS[@]}"; do
    log "deleting cluster '$c'"
    kind delete cluster --name "$c" 2>/dev/null || true
  done
}

prune_dns() {
  step "Removing local DNS configuration"
  if [ -f "$DNS_PIDFILE" ]; then
    sudo kill "$(cat "$DNS_PIDFILE")" 2>/dev/null || true
    sudo rm -f "$DNS_PIDFILE"
  fi
  # stop any stray dnsmasq bound to our config
  sudo pkill -f "dnsmasq.*${DNS_CONFFILE}" 2>/dev/null || true
  sudo rm -f "$DNS_CONFFILE"

  if [ -f "$RESOLVED_DROPIN" ]; then
    sudo rm -f "$RESOLVED_DROPIN"
    sudo systemctl restart systemd-resolved 2>/dev/null || true
  fi
  # remove the /etc/hosts fallback block, if present
  sudo sed -i '/# gitops-lab/d' /etc/hosts 2>/dev/null || true
}

prune_contexts() {
  step "Removing kube contexts"
  for c in "${CLUSTERS[@]}"; do
    kubectl config delete-context "$(ctx "$c")" 2>/dev/null || true
    kubectl config delete-cluster "$(ctx "$c")" 2>/dev/null || true
    kubectl config delete-user "$(ctx "$c")" 2>/dev/null || true
  done
}

prune_floci() {
  require_cmd docker || return
  step "Stopping floci (local AWS emulator)"
  if docker ps -a --format '{{.Names}}' | grep -qx "$FLOCI_CONTAINER"; then
    docker rm -f "$FLOCI_CONTAINER" >/dev/null 2>&1 && log "removed floci container" || true
  else
    log "floci container not present"
  fi
  docker image inspect "$FLOCI_IMAGE" >/dev/null 2>&1 && docker rmi "$FLOCI_IMAGE" >/dev/null 2>&1 \
    && log "removed floci image" || true
}

# Remove only the Docker artifacts install.sh created: kind node containers and
# their volumes (matched by kind's per-cluster label), the shared kind network,
# and the node image. Nothing else on the host's Docker is touched.
prune_docker() {
  require_cmd docker || { warn "docker not found; skipping docker cleanup"; return; }
  step "Removing lab Docker artifacts (containers, volumes, network, image)"

  for c in "${CLUSTERS[@]}"; do
    local ids
    ids="$(docker ps -aq --filter "label=io.x-k8s.kind.cluster=$c" 2>/dev/null)"
    if [ -n "$ids" ]; then
      log "removing '$c' node container(s) + volumes"
      # -v also drops the anonymous volumes kind attached to the node.
      echo "$ids" | xargs -r docker rm -f -v 2>/dev/null || true
    fi
    docker volume ls -q --filter "label=io.x-k8s.kind.cluster=$c" 2>/dev/null \
      | xargs -r docker volume rm -f 2>/dev/null || true
  done

  # The 'kind' network is shared by all kind clusters; remove it only once empty.
  if docker network inspect kind >/dev/null 2>&1; then
    if docker network rm kind >/dev/null 2>&1; then
      log "removed docker network 'kind'"
    else
      warn "docker network 'kind' still in use by another cluster; left in place"
    fi
  fi

  # The node image install.sh pulled (pinned in lib/common.sh).
  if docker image inspect "$NODE_IMAGE" >/dev/null 2>&1; then
    log "removing node image $NODE_IMAGE"
    docker rmi "$NODE_IMAGE" 2>/dev/null || true
  fi
}

prune_tools() {
  [ "$REMOVE_TOOLS" -eq 1 ] || { log "keeping CLI tools (pass --tools to remove)"; return; }
  step "Removing installed CLI tools"
  for t in kubectl kind k9s argocd; do
    sudo rm -f "/usr/local/bin/$t" 2>/dev/null || true
  done
}

main() {
  log "Pruning GitOps Enterprise Lab"
  prune_clusters
  prune_floci
  prune_dns
  prune_contexts
  prune_docker
  prune_tools
  log "DONE — environment cleaned."
}

main "$@"
