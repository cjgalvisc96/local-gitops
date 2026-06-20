---
description: Promote an app change from DEV to PROD via Git (Argo CD then syncs).
argument-hint: <app> [what changed, e.g. image tag]
---

Promote the application `$ARGUMENTS` from DEV to PROD using the `promote-app`
skill: diff the dev/prod overlays, carry the proven change into the prod overlay
only (keeping prod-specific identity), validate with `kustomize build`, and
commit with a `promote(...)` message. Do not touch the running cluster — the
promotion is a Git change that Argo CD reconciles.
