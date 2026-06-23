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
task install        # build the lab (clusters, Gitea, per-cluster Argo CD, platform)
task install:app    # same, plus deploy the external todo-app (DEPLOY_APP=true)
```

`install.sh` is idempotent — re-run it any time. It:

1. Verifies dependencies (Docker, Git, curl).
2. Installs the pinned tools (via mise).
3. Sets up the AWS profile, starts floci (local AWS emulator), and applies the
   app's local Terraform stack against it — the **same** stack the `tf-floci`
   pipeline uses, with state shared in floci S3 (see [CI/CD](cicd.md)). This
   provisions the ECR repo + SSM parameters.
4. Creates the three kind clusters.
5. Detects the live kind bridge subnet and derives all addresses from it.
6. Installs MetalLB and ingress-nginx.
7. Installs Gitea and seeds the GitOps repositories.
8. Installs Argo CD on `dev` and `prod` and bootstraps each cluster's `root` app.
9. Builds/loads the app image (only with `DEPLOY_APP=true`).
10. Wires DNS and prints the access URLs.

## Access

After install, the lab prints its URLs. The defaults:

| URL | What | Credentials |
|-----|------|-------------|
| `http://gitea.dev.local` | Gitea | `gitea_admin` / `adminadmin1` |
| `http://argo.dev.local`, `http://argo.prod.local` | Argo CD | `admin` / see below |
| `http://grafana.dev.local`, `http://grafana.prod.local` | Grafana | see chart values |

Each workload cluster has its own Argo CD admin password:

```bash
task argo:password      # prints admin password for kind-dev and kind-prod
```

DNS is wired automatically: a dedicated `dnsmasq` on `127.0.0.1:5300` resolves
`*.dev.local` / `*.prod.local` to the right cluster's ingress IP, via a
`systemd-resolved` drop-in (no manual `/etc/hosts` edits). On hosts without
systemd-resolved the installer falls back to an automated `/etc/hosts` block.
See [Networking & DNS](networking.md).

## Tear down

```bash
task prune          # remove clusters, floci, DNS drop-ins and Docker artifacts
task prune:all      # the above AND uninstall the mise-managed CLI tools
```

`prune.sh` is the exact inverse of `install.sh` — it cleans up the DNS drop-in,
the `/etc/hosts` marker block (`# gitops-lab`) and the global mise activation line
it added, leaving the host as it was.
