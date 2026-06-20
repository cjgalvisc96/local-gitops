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

# MetalLB L2 pools — all clusters share the docker "kind" bridge (172.18.0.0/16),
# so pools MUST NOT overlap. Each cluster announces a distinct slice.
export MGMT_POOL="172.18.255.200-172.18.255.209"
export DEV_POOL="172.18.255.210-172.18.255.219"
export PROD_POOL="172.18.255.220-172.18.255.229"

# Local DNS — 5300 avoids the mDNS port (5353) that avahi may hold.
export DNS_PORT="5300"
export DNS_PIDFILE="/tmp/gitops-dnsmasq.pid"
export DNS_CONFFILE="/tmp/gitops-dnsmasq.conf"
export RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/gitops-lab.conf"
export LAB_DOMAINS=("dev.local" "prod.local")

# Gitea
export GITEA_ADMIN_USER="gitea_admin"   # 'admin' is reserved in Gitea
export GITEA_ADMIN_PASSWORD="adminadmin1"
export GITEA_ORG="gitops"
export GITEA_REPOS=("platform-config" "gitops-apps")

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
# host is reachable from pods via the kind bridge gateway (172.18.0.1).
export FLOCI_CLUSTER_ENDPOINT="http://172.18.0.1:${FLOCI_PORT}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PROFILE_NAME="floci"   # local profile created in ~/.aws by install.sh

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
