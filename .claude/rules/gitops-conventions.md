# GitOps conventions (project rules)

Apply these whenever working in this repo.

## The core invariant
- The dev/prod clusters are **downstream of Git**. Change a manifest in
  `gitops-apps/` or `platform-config/`, commit, and let Argo CD reconcile.
- The **only** sanctioned imperative surface is the bootstrap layer
  (`install.sh` / `bootstrap/`). Never `kubectl apply`/`helm upgrade` a workload
  onto dev/prod by hand.

## Structure
- Apps & stacks are **base + per-env overlays** (Kustomize). Env-specific values
  live in the overlay, never hard-coded in the base.
- One app per namespace; ingress hosts are `gitea|argo|grafana|<app>.<env>.local`.
- Each workload cluster (dev, prod) runs its **own** Argo CD; its `root` app
  recurses `platform-config/envs/<env>` (app-of-apps). No ApplicationSets — a new
  stack is a new `Application` file in that dir. Management runs only Gitea.
- Tool versions are pinned in `mise.toml` (installed globally by `install.sh`);
  charts/images are pinned in `lib/common.sh` / manifests. One source of truth,
  no floating `latest` in the GitOps layer. Drive workflows via `Taskfile.yml`.

## Code style
- Well-written code explains itself: prefer clear names and structure over
  comments. Don't add banner/section comments or narrate the obvious.
- Keep the rare comment that records a non-obvious *why* (a workaround, a
  load-bearing marker string), never a *what*.

## Security
- No secret values in Git. Use `ExternalSecret` → `ClusterSecretStore` (AWS SSM
  via floci). Credentials for floci are dummy (`test`/`test`).

## Environment separation
- AppProjects scope `destinations` (by cluster name) and `sourceRepos`. Don't
  widen them to "make something work" — fix the manifest instead.

## Promotion
- Prove a change in **DEV** first, then update the matching **PROD** overlay.
  Never edit both blindly in one shot.

## Before you finish
- `kustomize build` every overlay you touched; `helm template` any chart you
  changed; `bash -n` + `shellcheck` any script. A change that doesn't render
  isn't done.
