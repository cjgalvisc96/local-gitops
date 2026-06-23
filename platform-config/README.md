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
```

The four files above are the **core platform** (always present). Everything else
in `envs/<env>/` is an **app registration**, present only with `DEPLOY_APP=true`
and owned by the app, not the platform — e.g. `todo-app.yaml` (the app's Helm
chart) and `dependencies-<env>.yaml` (the app's own datastores), both sourced
from the app's own repo. Apps bring their own namespace, RBAC, datastores and
floci/SSM seed; the platform stays app-agnostic.

The `root` app sets `directory.recurse: true`, so dropping a new `Application`
into `envs/<env>/` (plus one `sourceRepos` line in `project.yaml`) is enough —
no generators or ApplicationSets. Platform manifests live in `gitops-apps`; app
manifests live in the app's repo. Argo clones each from Gitea over its pinned
LoadBalancer IP.

Promote by proving a change in `envs/dev` (or its `gitops-apps` overlay) first,
then mirroring it into the `prod` counterpart.
