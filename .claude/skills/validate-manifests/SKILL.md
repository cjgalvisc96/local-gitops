---
name: validate-manifests
description: Validate the GitOps lab — build every Kustomize overlay, render every Helm chart with its values, parse all YAML, and lint the shell scripts. Use before committing or pushing changes to gitops-apps/, platform-config/, bootstrap/, or the scripts.
---

# Validate manifests

Run the full static-validation sweep and report a concise pass/fail per area.

## Steps

1. **Kustomize overlays** — build each leaf overlay:
   ```bash
   for d in gitops-apps/apps/overlays/*/* \
            gitops-apps/observability/overlays/* \
            gitops-apps/platform/overlays/*; do
     kustomize build "$d" >/dev/null && echo "OK  $d" || echo "FAIL $d"
   done
   ```

2. **Helm renders** — confirm chart values still apply:
   ```bash
   helm template gitea gitea/gitea --version "$GITEA_CHART_VERSION" \
     -f bootstrap/gitea/values.yaml >/dev/null
   helm template ingress-nginx ingress-nginx \
     --repo https://kubernetes.github.io/ingress-nginx \
     --version 4.11.3 -f bootstrap/ingress-nginx/values.yaml >/dev/null
   ```

3. **YAML parse** — every `*.yaml` outside `app/` must `yaml.safe_load_all`.

4. **Scripts** — `bash -n` + `shellcheck -S warning` on `install.sh`,
   `prune.sh`, `lib/common.sh`.

## Output
One line per check: `OK`/`FAIL` + path. End with a single summary verdict.
Do not modify files — this skill only validates.

> `kustomize` not installed? grab it from the kubernetes-sigs releases, or use
> `kubectl kustomize <dir>`.
