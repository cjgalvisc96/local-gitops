---
name: promote-app
description: Promote an application change from DEV to PROD the GitOps way — diff the dev vs prod overlay, copy the proven change (e.g. image tag, config) into the prod overlay, validate, and commit so Argo CD syncs it. Use when asked to promote/release an app to production.
---

# Promote DEV → PROD

Promotion is a **Git change**, not a cluster action.

## Inputs
- `app` (e.g. `app1`) and the change being promoted (image tag, config value).

## Steps
1. Show what differs between the environments for this app:
   ```bash
   diff -ru gitops-apps/apps/overlays/dev/<app> \
            gitops-apps/apps/overlays/prod/<app> || true
   ```
2. Confirm the change is healthy in DEV first
   (`argocd app get <app>-dev` → Synced/Healthy), or ask the user to confirm.
3. Apply the same change to the **prod** overlay only
   (`gitops-apps/apps/overlays/prod/<app>/`). Keep prod-specific values
   (host, color/message, replicas) intact — promote the *artifact/config*, not
   the environment identity.
4. Validate: `kustomize build gitops-apps/apps/overlays/prod/<app>`.
5. Commit with a clear message, e.g.
   `promote(<app>): dev→prod <what changed>`, and push so Argo CD syncs PROD.

## Guardrails
- Never edit dev and prod in the same blind sweep — DEV is the proving ground.
- Don't touch the running prod cluster directly; let Argo reconcile from Git.
