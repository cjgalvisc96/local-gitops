# GitOps Enterprise Lab (2026)

A fully local, reproducible GitOps platform: three Kubernetes clusters managed
from Git, installable with a single command. See [NEXT-STEPS.md](NEXT-STEPS.md)
for the full goal.

```
                 ┌─────────────┐        ┌─────────────┐
   Gitea  ◀──────│  management │──────▶ │   Argo CD   │
 (git server)    │   cluster   │        │ (app-of-apps)│
                 └─────────────┘        └──────┬──────┘
                                  GitOps sync   │
                        ┌──────────────────────┴───────────────────────┐
                        ▼                                               ▼
                 ┌─────────────┐                                 ┌─────────────┐
                 │ dev cluster │                                 │ prod cluster│
                 │ apps + OTel │                                 │ apps + OTel │
                 │ + Grafana   │                                 │ + Grafana   │
                 └─────────────┘                                 └─────────────┘
```

## Quick start

```bash
./install.sh      # build & wire everything (idempotent; re-runnable)
./prune.sh        # tear it all down  (--tools also removes installed binaries)
```

`install.sh` performs the 11 steps from NEXT-STEPS.md: verify deps → install
tools → create clusters → MetalLB → ingress-nginx → Gitea (+seed repos) →
Argo CD → register dev/prod → bootstrap root app → DNS → print URLs.

## How it fits together

- **Bootstrap layer** (`install.sh`, `bootstrap/`): kind, MetalLB, ingress-nginx,
  Gitea and Argo CD installed imperatively on the management cluster.
- **GitOps layer** (`platform-config/`, `gitops-apps/`): pushed into Gitea and
  reconciled by Argo CD onto dev/prod — applications, OpenTelemetry, Grafana,
  ingresses, RBAC, ConfigMaps and a floci-backed SecretStore.

| Repo | Role |
|------|------|
| `platform-config/` | Argo CD projects + ApplicationSets (the control repo) |
| `gitops-apps/`     | Kustomize manifests for apps, observability, platform |

### Working in this repo

- **`.agents/`** — multi-agent harness: role personas (lead, architect,
  developer, tester, devops, sre) that operate the lab, each scoped to a part of
  the tree. See [.agents/README.md](.agents/README.md).
- **`.claude/`** — Claude Code `skills/` (`validate-manifests`, `promote-app`),
  `rules/` (GitOps conventions), and `commands/` (`/validate`, `/promote`,
  `/status`).

## Access (after install)

| URL | What |
|-----|------|
| http://gitea.dev.local | Gitea (`gitea_admin` / `adminadmin1`) |
| http://argo.dev.local · http://argo.prod.local | Argo CD (`admin` / see below) |
| http://grafana.dev.local · http://grafana.prod.local | Grafana |
| http://app1.dev.local · http://app2.dev.local | DEV apps |
| http://app1.prod.local · http://app2.prod.local | PROD apps |

```bash
# Argo CD admin password
kubectl --context kind-management -n argocd get secret \
  argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

DNS is wired automatically: a dedicated `dnsmasq` on `127.0.0.1:5300` resolves
`*.dev.local` / `*.prod.local` to the right cluster's ingress IP, routed there by
a `systemd-resolved` drop-in (no manual `/etc/hosts` edits). On hosts without
systemd-resolved the installer falls back to an automated `/etc/hosts` block.

## Design notes & assumptions

- **Linux**: MetalLB IPs on the kind docker network (`172.18.0.0/16`) are
  routable from the host on Linux, which makes the LoadBalancer + DNS approach
  work without port juggling.
- **Cross-cluster registration**: dev/prod are registered with Argo CD using
  each control-plane container's docker IP (`https://<ip>:6443`), which is in the
  kind apiserver cert SANs and reachable from management pods on the shared network.
- **Management UI naming**: Gitea/Argo CD live on the management cluster but are
  aliased under `*.dev.local` / `*.prod.local` to match the URL list in the spec.
- **floci (AWS)**: `install.sh` starts floci (the local AWS emulator) as a Docker
  container on `:4566`, seeds SSM parameters and ECR repos, and the External
  Secrets Operator in each cluster pulls from it. Pods reach floci's
  host-published port via the kind bridge gateway (`172.18.0.1:4566`); the host
  seeds via `localhost:4566`. `prune.sh` stops and removes it. The AWS CLI is
  auto-installed if missing. See https://github.com/floci-io/floci.
- **Eventual consistency**: the `ClusterSecretStore`/`ExternalSecret` depend on
  ESO's CRDs (installed by a separate Application); Argo self-heal reconciles
  them once the operator is up.
```
