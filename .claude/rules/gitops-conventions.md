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
- One app per namespace; ingress hosts are `gitea|argo|grafana|appN.<env>.local`.
- Versions (tools, charts, images) are pinned in `lib/common.sh` / manifests —
  one source of truth, no floating `latest` in the GitOps layer.

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
