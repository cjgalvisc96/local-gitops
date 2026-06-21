#!/usr/bin/env bash
# =============================================================================
# Shared library for install.sh / prune.sh
# Sourced, never executed directly.
# =============================================================================

# ----------------------------------------------------------------------------
# Cluster + version configuration (single source of truth)
# ----------------------------------------------------------------------------
export MGMT_CLUSTER="management"
export DEV_CLUSTER="dev"
export PROD_CLUSTER="prod"
export CLUSTERS=("$MGMT_CLUSTER" "$DEV_CLUSTER" "$PROD_CLUSTER")

# kubectl/kind must stay within one minor of the node image.
export NODE_IMAGE="kindest/node:v1.31.4"
export KUBECTL_VERSION="v1.31.4"
export ARGOCD_VERSION="v2.13.2"
export METALLB_VERSION="v0.14.8"
export INGRESS_NGINX_VERSION="4.11.3"   # helm chart version
export GITEA_CHART_VERSION="10.6.0"     # gitea helm chart version

# MetalLB L2 pools, the pinned Gitea LB IP, and the floci gateway are all derived
# from the docker "kind" bridge's actual /16 at install time (see apply_net_prefix
# below). The committed default is 172.18.x, but if that subnet is taken (e.g. by
# the todo-app compose network) kind lands on another /16 and install.sh adapts.

# Local DNS — 5300 avoids the mDNS port (5353) that avahi may hold.
export DNS_PORT="5300"
export DNS_PIDFILE="/tmp/gitops-dnsmasq.pid"
export DNS_CONFFILE="/tmp/gitops-dnsmasq.conf"
export RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/gitops-lab.conf"
export LAB_DOMAINS=("dev.local" "prod.local")

# Argo CD runs in EACH workload cluster (one Argo per env), not on management.
export ARGO_CLUSTERS=("$DEV_CLUSTER" "$PROD_CLUSTER")

# Gitea lives on the management cluster but must be cloneable from the dev/prod
# Argo instances. We give it a pinned MetalLB LoadBalancer IP (in the management
# pool) so its git URL is stable and reachable across clusters on the kind bridge.
export GITEA_ADMIN_USER="gitea_admin"   # 'admin' is reserved in Gitea
export GITEA_ADMIN_PASSWORD="adminadmin1"
export GITEA_ORG="gitops"
# GITEA_GIT_IP / GITEA_GIT_URL are set by apply_net_prefix (subnet-derived).

# Git repositories pushed into Gitea by install.sh.
export GITEA_REPOS=("platform-config" "gitops-apps")

# The application to deploy (its own repo + Helm chart). Pushed to Gitea too.
# DEPLOY_APP gates the whole todo-app path (image build, repo mirror, and the
# todo-app + postgres/redis Argo Applications). Off by default for now:
#   DEPLOY_APP=true ./install.sh   # to deploy the app
export DEPLOY_APP="${DEPLOY_APP:-false}"
export APP_REPO_NAME="modular-monolithic-app"
export APP_REPO_PATH="${APP_REPO_PATH:-$HOME/Documents/Personal/modular-monolithic-app}"
export APP_IMAGE="local/todo-app"       # built from the app's Dockerfile

# Docker "project" grouping. Like ~/Documents/Personal/modular-monolithic-app
# groups its containers under the Compose project 'todo-app', we stamp the same
# label Docker Desktop / `docker compose ls` use onto the containers this lab
# creates directly (floci), so they show up under one project.
#   NOTE: kind node containers are created by kind, which exposes no hook to set
#   custom Docker labels, and Docker can't relabel a running container — so the
#   three *-control-plane nodes keep grouping under kind's own labels instead.
export PROJECT_NAME="${PROJECT_NAME:-local-gitops}"

# floci (local AWS emulator) — https://github.com/floci-io/floci
export FLOCI_CONTAINER="floci"
export FLOCI_IMAGE="floci/floci:latest"
# floci mounts the docker socket and spawns helper containers/images on demand
# (ECR backing registry, RDS postgres, ...). Cleaned up by prune.sh.
export FLOCI_HELPER_IMAGES="registry:2 postgres:16-alpine"
export FLOCI_PORT="4566"
# Endpoint as seen from the host (install.sh seeding) ...
export FLOCI_HOST_ENDPOINT="http://localhost:${FLOCI_PORT}"
# ... and as seen from inside the kind clusters: floci's published port on the
# host is reachable from pods via the kind bridge gateway. FLOCI_CLUSTER_ENDPOINT
# is set by apply_net_prefix (subnet-derived).
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PROFILE_NAME="floci"   # local profile created in ~/.aws by install.sh

# ----------------------------------------------------------------------------
# Network-prefix derivation (kind docker bridge is /16; we adapt to whatever
# subnet it actually got).
# ----------------------------------------------------------------------------
# The prefix baked into the committed manifests. apply_net_prefix rewrites these
# at install time when the live kind bridge differs.
export DEFAULT_NET_PREFIX="172.18"
export NET_PREFIX="$DEFAULT_NET_PREFIX"

# apply_net_prefix <a.b> — recompute every subnet-derived address from a /16
# prefix (e.g. "172.19"). Pools live in the high .255.x range; Gitea's pinned LB
# is .255.209 (management pool); the floci gateway is .0.1.
apply_net_prefix() {
  NET_PREFIX="$1"
  export NET_PREFIX
  export MGMT_POOL="${NET_PREFIX}.255.200-${NET_PREFIX}.255.209"
  export DEV_POOL="${NET_PREFIX}.255.210-${NET_PREFIX}.255.219"
  export PROD_POOL="${NET_PREFIX}.255.220-${NET_PREFIX}.255.229"
  export GITEA_GIT_IP="${NET_PREFIX}.255.209"
  export GITEA_GIT_URL="http://${GITEA_GIT_IP}:3000/${GITEA_ORG}"
  export FLOCI_GW="${NET_PREFIX}.0.1"
  export FLOCI_CLUSTER_ENDPOINT="http://${FLOCI_GW}:${FLOCI_PORT}"
}
apply_net_prefix "$DEFAULT_NET_PREFIX"   # defaults; install.sh re-applies the live prefix

# subst_net — filter stdin, rewriting the committed default prefix to the live
# one (no-op when they match). Used when applying/pushing manifests that embed
# the Gitea LB IP or the floci gateway.
subst_net() {
  if [ "$NET_PREFIX" = "$DEFAULT_NET_PREFIX" ]; then
    cat
  else
    sed "s/${DEFAULT_NET_PREFIX}\./${NET_PREFIX}./g"
  fi
}

# subst_net_tree <dir> — rewrite the prefix in-place across a directory of YAML.
subst_net_tree() {
  [ "$NET_PREFIX" = "$DEFAULT_NET_PREFIX" ] && return 0
  find "$1" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
    | xargs -0 -r sed -i "s/${DEFAULT_NET_PREFIX}\./${NET_PREFIX}./g"
}

# Repo root (directory containing install.sh)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
_c() { printf '\033[%sm' "$1"; }
log()   { echo -e "$(_c '1;36')[gitops]$(_c 0) $*"; }
warn()  { echo -e "$(_c '1;33')[warn]$(_c 0)  $*" >&2; }
err()   { echo -e "$(_c '1;31')[error]$(_c 0) $*" >&2; }
step()  { echo -e "\n$(_c '1;35')==>$(_c 0) $(_c 1)$*$(_c 0)"; }
die()   { err "$*"; exit 1; }

# ----------------------------------------------------------------------------
# Context helpers
# ----------------------------------------------------------------------------
ctx() { echo "kind-$1"; }                       # cluster name -> kube context
kc()  { kubectl --context "$(ctx "$1")" "${@:2}"; }   # kc <cluster> <args...>

# Docker IP of a cluster's control-plane on the kind network (reachable in-cluster).
cluster_internal_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    "$1-control-plane" 2>/dev/null
}

require_cmd() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------------------
# OS / package-manager detection (Debian, Fedora, Arch, RedHat, macOS)
# ----------------------------------------------------------------------------
# Echo the host's package manager, or "" if none is recognised.
detect_pkg_mgr() {
  if require_cmd brew;    then echo "brew";    return; fi
  if require_cmd apt-get; then echo "apt-get"; return; fi
  if require_cmd dnf;     then echo "dnf";     return; fi
  if require_cmd yum;     then echo "yum";     return; fi
  if require_cmd pacman;  then echo "pacman";  return; fi
  if require_cmd zypper;  then echo "zypper";  return; fi
  echo ""
}

# pkg_install <pkg...> — best-effort install of a SYSTEM package (e.g. dnsmasq)
# via whatever package manager the host has. CLI tooling goes through mise; this
# is only for things mise doesn't provide.
pkg_install() {
  local mgr; mgr="$(detect_pkg_mgr)"
  [ -n "$mgr" ] || { warn "no supported package manager found; please install manually: $*"; return 1; }
  log "installing system package(s) via ${mgr}: $*"
  case "$mgr" in
    brew)    brew install "$@" ;;
    apt-get) sudo apt-get update -qq && sudo apt-get install -y "$@" ;;
    dnf|yum) sudo "$mgr" install -y "$@" ;;
    pacman)  sudo pacman -Sy --noconfirm "$@" ;;
    zypper)  sudo zypper install -y "$@" ;;
  esac
}

# ----------------------------------------------------------------------------
# mise (https://mise.jdx.dev) — manages the CLI toolchain pinned in mise.toml.
# ----------------------------------------------------------------------------
export MISE_DATA_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}"

# Echo each pinned tool from mise.toml as "name@version" (one per line),
# tolerating inline comments. Used to install tools globally and to prune them.
mise_tool_args() {
  awk '
    /^\[tools\]/ { f=1; next }
    /^\[/        { f=0 }
    f && /=/ && match($0, /"[^"]+"/) {
      name=$0; sub(/[ \t]*=.*/, "", name); gsub(/[ \t]/, "", name)
      ver=substr($0, RSTART+1, RLENGTH-2)
      if (name != "") print name "@" ver
    }' "${REPO_ROOT}/mise.toml"
}

# Prepend mise's bin + shims to PATH so tools it installs are callable for the
# rest of the script (and idempotent if already present).
ensure_mise_path() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;            *) PATH="$HOME/.local/bin:$PATH" ;;
  esac
  case ":$PATH:" in
    *":$MISE_DATA_DIR/shims:"*) ;;        *) PATH="$MISE_DATA_DIR/shims:$PATH" ;;
  esac
  export PATH
}
