# GitOps Enterprise Lab

A fully local, reproducible GitOps platform: three Kubernetes clusters (kind)
managed from Git, installable with a single command. `dev` and `prod` each run
their own Argo CD and reconcile from an in-cluster Gitea — no cloud account
required.

## Quick start

```bash
task tools      # install the pinned CLI toolchain (mise)
task install    # build & wire everything (idempotent, re-runnable)
task prune      # tear it all down
```

## Documentation

The full documentation lives in [MkDocs](https://www.mkdocs.org/) — one place,
read it in your browser:

```bash
task docs:serve   # http://127.0.0.1:8080
```

It covers getting started, architecture, the repository layout, the GitOps
workflow and DEV→PROD promotion, observability, networking/DNS, secrets, and the
full task reference. The source is in [`docs/`](docs/) (`mkdocs.yml`).

## At a glance

- **Multi-cluster** — `management` (Gitea), `dev`, `prod` (each its own Argo CD).
- **App-of-apps per env** — `platform-config/envs/<env>` (no ApplicationSets).
- **Kustomize** base + per-env overlays in `gitops-apps/`.
- **Observability** — metrics, logs and traces via OpenTelemetry → Prometheus /
  Loki / Tempo → Grafana.
- **Secrets** — External Secrets Operator backed by floci (local AWS / SSM); no
  secret values in Git.
- **Pinned everything** — tools in `mise.toml`, charts/images in `lib/common.sh`.

The `dev`/`prod` clusters are downstream of Git: change a manifest, commit, and
let Argo CD reconcile. The only imperative surface is `install.sh` / `prune.sh`.
