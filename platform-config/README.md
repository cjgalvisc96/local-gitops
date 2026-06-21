# platform-config

The **GitOps control repository**. Each workload cluster runs its own Argo CD,
and that cluster's `root` Application (app-of-apps) watches one directory here:

```
envs/dev/    Argo Applications the DEV cluster's Argo CD reconciles
envs/prod/   Argo Applications the PROD cluster's Argo CD reconciles
```

Every `envs/<env>/` holds, for that environment:

```
project.yaml           AppProject <env> (scopes sourceRepos to the Gitea repos)
platform.yaml          → gitops-apps/platform/overlays/<env>
observability.yaml     → gitops-apps/observability/overlays/<env>
external-secrets.yaml  External Secrets Operator (Helm chart)
dependencies.yaml      → gitops-apps/dependencies/base   (only with DEPLOY_APP=true)
todo-app.yaml          the external app's Helm chart     (only with DEPLOY_APP=true)
```

The `root` app sets `directory.recurse: true`, so dropping a new `Application`
into `envs/<env>/` is enough — no generators or ApplicationSets. The manifests
these Applications point at live in the `gitops-apps` repo; Argo clones both
repos from Gitea over its pinned LoadBalancer IP.

Promote by proving a change in `envs/dev` (or its `gitops-apps` overlay) first,
then mirroring it into the `prod` counterpart.
