# Getting started

## Prerequisites

- **Linux** with Docker running. MetalLB IPs on the kind docker network are
  routable from a Linux host, which makes the LoadBalancer + DNS approach work
  without port juggling.
- **Git** and **curl**.
- [**mise**](https://mise.jdx.dev) to install the pinned CLI toolchain. The
  versions live in `mise.toml`; nothing floats on `latest` except Trivy.

```bash
task tools     # mise install + reshim — kubectl, kind, helm, argocd, kustomize, awscli, trivy, uv
```

The documentation toolchain (MkDocs + the Material theme) is run on demand via
`uv` (`uvx`) at pinned versions — see [Operations](operations.md#documentation).

## Install

```bash
task install        # build the lab (infra + Gitea + per-EKS Argo CD + observability)
```

The platform installs **app-agnostic** — it carries no specific app. Apps onboard themselves into
the running lab (the todo-app does this with its `gitea:create-repo` / `gitea:ship` tasks); see the
[Launch](launch.md) page for the end-to-end "how to run everything".

`task install` runs three stages, in order — and is idempotent, so you can re-run it any time:

1. **Infra** — Terraform/Terragrunt (`infra/terragrunt/lab → infra/terraform/lab`) creates the
   `floci` container (local AWS emulator), the kind `management` cluster, and the two **floci-EKS**
   k3s clusters (`floci-eks-todo-app-dev` on `:6443`, `floci-eks-todo-app-prod` on `:6444`). A second
   apply provisions the Gitea Actions runner once Gitea has issued a token.
2. **Management Kubernetes layer** (`install.sh`) — verifies dependencies (Docker, Git, curl),
   installs the pinned tools, sets up the AWS profile, detects the live kind bridge subnet and derives
   all addresses from it, installs MetalLB + ingress-nginx + Gitea on the management cluster, seeds the
   Gitea `gitops` org and the `gitops-apps` repo, and wires DNS.
3. **Per-EKS bootstrap** (`task eks:bootstrap ENV=dev` and `ENV=prod`) — into **each** floci-EKS
   cluster: a single-IP MetalLB pool (dev `.230`, prod `.240`) + ingress-nginx + Argo CD + an
   observability Argo `Application` synced from `gitops-apps/observability/overlays/<env>`.

When it finishes, `argo.dev/prod.local` and `grafana.dev/prod.local` are **already live (http)** —
the platform owns and stands up the workload clusters, so Argo CD and Grafana are up before any app is
deployed.

## Access

After install, the lab prints its URLs. The defaults:

Gitea and Grafana share the password `adminlocal1`; the Gitea user is `adminlocal`
(`admin` is reserved in Gitea), Grafana's is `admin`. Argo CD is `admin` with a
**per-cluster random** password — print it with `task argo:password ENV=<env>`.

| URL | What | Credentials |
|-----|------|-------------|
| `http://gitea.dev.local` | Gitea | `adminlocal` / `adminlocal1` |
| `http://argo.dev.local`, `http://argo.prod.local` | Argo CD | `admin` / `task argo:password ENV=<env>` |
| `http://grafana.dev.local`, `http://grafana.prod.local` | Grafana | `admin` / `adminlocal1` |

```bash
task argo:password ENV=dev   # prints the in-EKS Argo CD admin login (per-cluster, random)
```

Argo CD runs **insecure (HTTP)** behind ingress-nginx, so every URL is `http://`, never `https://`.

DNS is wired automatically: a dedicated `dnsmasq` on `127.0.0.1:5300` resolves
`*.dev.local` / `*.prod.local` to the right cluster's ingress IP, via a
`systemd-resolved` drop-in (no manual `/etc/hosts` edits). On hosts without
systemd-resolved the installer falls back to an automated `/etc/hosts` block.
See [Networking & DNS](networking.md).

## Tear down

```bash
task prune          # Terragrunt destroy (runner + kind + floci-EKS + floci) then host cleanup
task prune:all      # the above AND uninstall the mise-managed CLI tools
```

`task prune` runs `terragrunt destroy` (removing the runner, the kind management
cluster and the floci-EKS clusters and the floci container) then `prune.sh` for
host cleanup — the DNS drop-in, the `/etc/hosts` marker block (`# gitops-lab`) and
the global mise activation line it added, leaving the host as it was.
