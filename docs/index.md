# GitOps Enterprise Lab

A fully local, reproducible GitOps platform: three Kubernetes clusters managed
from Git, installable with a single command. It demonstrates how modern teams run
applications across multiple environments with Git as the single source of truth —
no cloud account required.

## What it gives you

- **Multi-cluster Kubernetes** — `management`, `dev`, `prod` (kind).
- **GitOps with Argo CD** — `dev` and `prod` each run their **own** Argo CD and
  reconcile from an in-cluster Gitea.
- **Self-hosted Git** — Gitea on the management cluster.
- **DEV → PROD promotion** — base + per-env Kustomize overlays.
- **Observability** — metrics, logs and traces via OpenTelemetry into
  Prometheus / Loki / Tempo, surfaced in Grafana.
- **Real ingress & load balancers** — ingress-nginx + MetalLB, friendly
  `*.dev.local` / `*.prod.local` URLs wired automatically.
- **Secrets without secrets in Git** — External Secrets Operator backed by a
  local AWS emulator (floci/SSM).

## Quick start

```bash
task tools     # install the pinned CLI toolchain (mise)
task install    # build & wire everything (idempotent, re-runnable)
task prune      # tear it all down
```

`task install` runs `./install.sh`, which is the only sanctioned imperative
surface. Everything that lands on `dev`/`prod` afterwards flows through Git and
Argo CD.

See [Getting started](getting-started.md) to run it, then
[Architecture](architecture.md) for how the pieces fit.

## The core idea

The `dev` and `prod` clusters are **downstream of Git**. You change a manifest in
`gitops-apps/` or `platform-config/`, commit, and let Argo CD reconcile. The only
imperative surface is the bootstrap layer (`install.sh` / `bootstrap/`). Nothing
is `kubectl apply`-ed onto a workload cluster by hand.
