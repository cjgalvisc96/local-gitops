---
description: Run the full static validation sweep over the GitOps lab (kustomize builds, helm renders, YAML parse, script lint).
---

Run the `validate-manifests` skill against the whole repository and report a
concise pass/fail summary per area (kustomize overlays, helm renders, YAML
parse, shell lint). Do not modify any files. If anything fails, show the
offending path and the error, and propose the minimal fix.
