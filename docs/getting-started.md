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
```

The platform installs **app-agnostic** — it carries no specific app. Apps onboard themselves into
the running lab (the todo-app does this with its `gitea:create-repo` / `argo:add-gitea-repo` /
`gitea:ship` tasks); see the [Launch](launch.md) page for the end-to-end "how to run everything".

`install.sh` is idempotent — re-run it any time. It:

1. Verifies dependencies (Docker, Git, curl).
2. Installs the pinned tools (via mise).
3. Sets up the AWS profile, starts floci (local AWS emulator), and applies the
   local Terraform stack against it — the **same** stack the `tf-floci`
   pipeline uses, with state shared in floci S3 (see [CI/CD](cicd.md)). This
   provisions the ECR repo + SSM parameters.
4. Creates the three kind clusters.
5. Detects the live kind bridge subnet and derives all addresses from it.
6. Installs MetalLB and ingress-nginx.
7. Installs Gitea and seeds the platform GitOps repositories (`platform-config`, `gitops-apps`).
8. Installs Argo CD on `dev` and `prod` (with a fixed admin password) and bootstraps each cluster's
   `root` app.
9. Wires DNS and prints the access URLs.

> `task install:app` (`DEPLOY_APP=true`) additionally keeps an app's Argo Applications in
> `platform-config` so Argo is pre-wired to deploy it. The recommended flow uses plain `task install`
> and lets the app fully self-onboard — see [Launch](launch.md).

## Access

After install, the lab prints its URLs. The defaults:

The lab uses **uniform credentials** — password `adminlocal1` everywhere. The
user is `admin` for everything except Gitea, which uses `adminlocal` (`admin` is
a reserved username in Gitea).

| URL | What | Credentials |
|-----|------|-------------|
| `http://gitea.dev.local` | Gitea | `adminlocal` / `adminlocal1` |
| `http://argo.dev.local`, `http://argo.prod.local` | Argo CD | `admin` / `adminlocal1` |
| `http://grafana.dev.local`, `http://grafana.prod.local` | Grafana | `admin` / `adminlocal1` |

```bash
task argo:password      # prints the Argo CD admin login for kind-dev and kind-prod
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
