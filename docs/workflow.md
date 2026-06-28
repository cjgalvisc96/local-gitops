# GitOps workflow

## The invariant

The `dev` and `prod` clusters are **downstream of Git**. You never `kubectl apply`
or `helm upgrade` a workload onto them. You change a manifest, commit, push to
Gitea, and the cluster's Argo CD reconciles it.

```
edit manifest ─▶ commit ─▶ push to Gitea ─▶ Argo CD syncs ─▶ cluster converges
```

## Make a change

1. Edit the relevant base or overlay under `gitops-apps/<stack>/…` (for the
   platform, that is the `observability` stack).
2. Validate locally before pushing:
   ```bash
   task validate          # render every overlay, parse YAML, lint scripts
   ```
3. Commit and push. Watch it land:
   ```bash
   task k8s:status        # clusters + Argo application health
   task k8s:sync ENV=dev  # force a hard refresh + sync if you don't want to wait
   ```

## Promote DEV → PROD

Promotion is a **Git change**, not a cluster action — `dev` and `prod` have
separate Argo CDs, so you promote by editing the prod side of the repo.

1. Prove the change in **DEV** first and confirm it is healthy:
   ```bash
   task k8s:apps ENV=dev   # in-EKS Argo applications on the dev cluster
   ```
2. Diff the two sides and copy the proven artifact/config into prod:
   ```bash
   diff -ru gitops-apps/<stack>/overlays/dev gitops-apps/<stack>/overlays/prod
   ```
   Promote the *image tag / config value* — keep prod-specific values (host,
   replicas, `values-prod.yaml`) intact.
3. Validate, commit (`promote(<app>): dev→prod <what changed>`), push. The PROD
   cluster's Argo CD syncs it.

!!! warning "Never edit dev and prod in one blind sweep"
    DEV is the proving ground. Widening an `AppProject`'s `destinations` /
    `sourceRepos` to "make something work" is not allowed — fix the manifest.

The `promote` task/skill encodes these steps.

!!! note "App image promotion is automated"
    The hand steps above are for **platform/stack** changes you edit in this repo.
    An onboarded app's *image* build and DEV→PROD promotion are automated by its
    Gitea Actions pipelines (build → push → bump `values-dev.yaml`; manual
    dispatch bumps `values-prod.yaml`) — see [CI/CD](cicd.md). Either way it stays
    a Git change Argo CD reconciles.
