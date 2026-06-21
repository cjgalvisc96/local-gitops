---
name: promote-app
description: Promote a proven change from DEV to PROD the GitOps way — diff the dev vs prod overlay (or env Application), copy the proven change (image tag, config value) into the prod side, validate, and commit so the PROD cluster's Argo CD syncs it. Use when asked to promote/release to production.
---

# Promote DEV → PROD

Promotion is a **Git change**, not a cluster action. dev and prod each have their
own Argo CD, so promoting means editing the prod side of the repo.

## Inputs
- The stack/app being promoted and what changed (image tag, config value).

## Steps
1. Show what differs between the environments. Pick the layer that holds the
   change:
   ```bash
   # an in-repo stack (platform, observability, dependencies):
   diff -ru gitops-apps/<stack>/overlays/dev gitops-apps/<stack>/overlays/prod || true
   # or the per-env Argo Application (e.g. the external todo-app's values):
   diff -u platform-config/envs/dev/<app>.yaml platform-config/envs/prod/<app>.yaml || true
   ```
2. Confirm the change is healthy in DEV first
   (`kubectl --context kind-dev -n argocd get applications.argoproj.io`), or ask
   the user to confirm.
3. Apply the same change to the **prod** side only. Keep prod-specific values
   (host, replicas, `values-prod.yaml`) intact — promote the *artifact/config*,
   not the environment identity.
4. Validate: `kustomize build gitops-apps/<stack>/overlays/prod` (for a stack),
   or `task validate`.
5. Commit with a clear message, e.g. `promote(<app>): dev→prod <what changed>`,
   and push so the PROD cluster's Argo CD syncs.

## Guardrails
- Never edit dev and prod in the same blind sweep — DEV is the proving ground.
- Don't touch the running prod cluster directly; let Argo reconcile from Git.
