#!/usr/bin/env bash
export MGMT_CLUSTER="management"
export CLUSTERS=("$MGMT_CLUSTER")

export NODE_IMAGE="kindest/node:v1.31.4"
export METALLB_VERSION="v0.14.8"
export INGRESS_NGINX_VERSION="4.11.3"
# Gitea chart 12.x ships Gitea >= 1.24 (Actions workflow-dispatch UI + API); 10.x shipped 1.22 without it.
export GITEA_CHART_VERSION="12.4.0"

export DNS_PORT="5300"
export DNS_PIDFILE="/tmp/gitops-dnsmasq.pid"
export DNS_CONFFILE="/tmp/gitops-dnsmasq.conf"
export RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/gitops-lab.conf"

# Grafana admin password is set separately in gitops-apps/observability/base/grafana.yaml — keep in sync.
export LAB_PASSWORD="adminlocal1"
export GITEA_ADMIN_USER="adminlocal"
export GITEA_ADMIN_PASSWORD="$LAB_PASSWORD"
export GITEA_ORG="gitops"

export GITEA_REPOS=("gitops-apps")

export APP_IMAGE="local/todo-app"

export PROJECT_NAME="${PROJECT_NAME:-local-gitops}"

export RUNNER_CONTAINER="gitea-runner"
export RUNNER_IMAGE="gitea/act_runner:0.2.11"
export RUNNER_NAME="lab-runner"

export FLOCI_CONTAINER="floci"
export FLOCI_IMAGE="floci/floci:latest"
export FLOCI_HELPER_IMAGES="registry:2 postgres:16-alpine"
export FLOCI_PORT="4566"
export FLOCI_HOST_ENDPOINT="http://localhost:${FLOCI_PORT}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PROFILE_NAME="floci"

export DEFAULT_NET_PREFIX="172.18"
export NET_PREFIX="$DEFAULT_NET_PREFIX"

apply_net_prefix() {
  NET_PREFIX="$1"
  export NET_PREFIX
  export MGMT_POOL="${NET_PREFIX}.255.200-${NET_PREFIX}.255.209"
  export EKS_DEV_IP="${NET_PREFIX}.255.230"
  export EKS_PROD_IP="${NET_PREFIX}.255.240"
  export GITEA_GIT_IP="${NET_PREFIX}.255.209"
  export GITEA_GIT_URL="http://${GITEA_GIT_IP}:3000/${GITEA_ORG}"
  export FLOCI_GW="${NET_PREFIX}.0.1"
}
apply_net_prefix "$DEFAULT_NET_PREFIX"

subst_net() {
  if [ "$NET_PREFIX" = "$DEFAULT_NET_PREFIX" ]; then
    cat
  else
    sed "s/${DEFAULT_NET_PREFIX}\./${NET_PREFIX}./g"
  fi
}

subst_net_tree() {
  [ "$NET_PREFIX" = "$DEFAULT_NET_PREFIX" ] && return 0
  find "$1" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
    | xargs -0 -r sed -i "s/${DEFAULT_NET_PREFIX}\./${NET_PREFIX}./g"
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

_c() { printf '\033[%sm' "$1"; }
log()   { echo -e "$(_c '1;36')[gitops]$(_c 0) $*"; }
warn()  { echo -e "$(_c '1;33')[warn]$(_c 0)  $*" >&2; }
err()   { echo -e "$(_c '1;31')[error]$(_c 0) $*" >&2; }
step()  { echo -e "\n$(_c '1;35')==>$(_c 0) $(_c 1)$*$(_c 0)"; }
die()   { err "$*"; exit 1; }

ctx() { echo "kind-$1"; }
kc()  { kubectl --context "$(ctx "$1")" "${@:2}"; }

require_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_pkg_mgr() {
  if require_cmd brew;    then echo "brew";    return; fi
  if require_cmd apt-get; then echo "apt-get"; return; fi
  if require_cmd dnf;     then echo "dnf";     return; fi
  if require_cmd yum;     then echo "yum";     return; fi
  if require_cmd pacman;  then echo "pacman";  return; fi
  if require_cmd zypper;  then echo "zypper";  return; fi
  echo ""
}

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

export MISE_DATA_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}"

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

ensure_mise_path() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;            *) PATH="$HOME/.local/bin:$PATH" ;;
  esac
  case ":$PATH:" in
    *":$MISE_DATA_DIR/shims:"*) ;;        *) PATH="$MISE_DATA_DIR/shims:$PATH" ;;
  esac
  export PATH
}
