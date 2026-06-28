# GitOps Enterprise Lab

A fully local, reproducible GitOps **platform**: a management cluster plus two
workload clusters managed from Git, installable with a single command. It
demonstrates how modern teams run applications across multiple environments with
Git as the single source of truth — no cloud account required.

This repository is the **platform**. It owns the clusters, the GitOps control
plane (Argo CD) and the observability stack. Apps — such as
`modular-monolithic-app` — live in their **own** repositories and deploy *onto*
this running platform; they no longer create clusters.

## What it gives you

- **Multi-cluster Kubernetes** — a `management` cluster (kind) plus two
  **floci-EKS** workload clusters, `dev` and `prod` (k3s containers emulating
  EKS on floci).
- **GitOps with Argo CD** — `dev` and `prod` each run their **own** Argo CD and
  reconcile from an in-cluster Gitea. The platform stands these up at install
  time, before any app exists.
- **Self-hosted Git** — Gitea on the management cluster.
- **CI/CD with Gitea Actions** — a host runner builds app images, pushes to floci
  ECR, applies the app's cloud infra (Terraform/Terragrunt on floci), and deploys
  via Git (see [CI/CD](cicd.md)).
- **DEV → PROD promotion** — DEV is automatic, PROD is a deliberate manual
  dispatch.
- **Observability** — metrics, logs and traces via OpenTelemetry into
  Prometheus / Loki / Tempo, surfaced in Grafana — **live before any app**.
- **Real ingress & load balancers** — ingress-nginx + MetalLB, friendly
  `*.dev.local` / `*.prod.local` URLs wired automatically.
- **Secrets without secrets in Git** — manifests reference secrets backed by a
  local AWS emulator (floci); secret values never live in Git.

## Quick start

```bash
task tools     # install the pinned CLI toolchain (mise)
task install    # build & wire everything (idempotent, re-runnable)
task prune      # tear it all down
```

`task install` provisions the infrastructure (Terraform/Terragrunt: floci, the
kind management cluster and the two floci-EKS clusters), runs `./install.sh` for
the management Kubernetes layer (Gitea), then bootstraps Argo CD + observability
into each floci-EKS cluster. Everything that lands on `dev`/`prod` afterwards
flows through Git and Argo CD.

See [Getting started](getting-started.md) to run it, then
[Architecture](architecture.md) for how the pieces fit.

## The core idea

The `dev` and `prod` clusters are **downstream of Git**. You change a manifest in
`gitops-apps/`, commit, and let Argo CD reconcile. The only imperative surface is
the bootstrap layer (Terraform, `install.sh`, the committed `bootstrap/`
manifests). Nothing is `kubectl apply`-ed onto a workload cluster by hand.
