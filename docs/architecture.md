# Architecture

## Three clusters

| Cluster | Runs |
|---------|------|
| `management` | Gitea (the in-cluster Git server) — and only Gitea |
| `dev` | its **own** Argo CD, the platform stacks, the dev apps |
| `prod` | its **own** Argo CD, the platform stacks, the prod apps |

There is **no central Argo CD**. Each workload cluster reconciles itself.

```
                 ┌──────────────┐
                 │  management  │   Gitea (git server)
                 │   cluster    │   the GitOps repos live here
                 └──────┬───────┘
            clone over pinned LB IP (<prefix>.255.209)
        ┌───────────────┴────────────────┐
        ▼                                 ▼
 ┌──────────────┐                  ┌──────────────┐
 │ dev cluster  │                  │ prod cluster │
 │  Argo CD     │                  │  Argo CD     │
 │  root app ──▶│ platform-config/ │  root app ──▶│ platform-config/
 │   envs/dev   │                  │   envs/prod  │
 │  platform    │                  │  platform    │
 │  observability│                 │  observability│
 │  + apps      │                  │  + apps      │
 └──────────────┘                  └──────────────┘
```

## App-of-apps, per environment

Each workload cluster's `root` Application points at one directory in the control
repo and recurses it:

- `dev` cluster → `platform-config/envs/dev`
- `prod` cluster → `platform-config/envs/prod`

That directory holds the environment's `AppProject` plus one Argo `Application`
per stack. Adding a stack is **a new `Application` file** in that directory (plus
one `sourceRepos` line in `project.yaml`) — there are **no ApplicationSets or
cluster generators**. This is deliberate: each Argo CD can only reach its own
cluster, so a generator that spans clusters would not work.

```
platform-config/envs/dev/
├── project.yaml              AppProject "dev" — scopes sourceRepos & destinations
├── platform.yaml             → gitops-apps/platform/overlays/dev
├── observability.yaml        → gitops-apps/observability/overlays/dev
├── external-secrets.yaml     External Secrets Operator (Helm)
├── dependencies-dev.yaml     app datastores      (only with DEPLOY_APP=true)
└── todo-app.yaml             the external app    (only with DEPLOY_APP=true)
```

`envs/prod/` mirrors it. The first three files are the **core platform**, always
present. The rest are app registrations, owned by the app, present only when the
app is deployed.

## Platform vs. app boundary

The **platform** owns generic primitives only: clusters, Argo CD, the External
Secrets Operator + `aws-ssm` store, ingress, DNS, floci and Gitea. An **app**
owns everything app-specific in its own repo — Helm chart, namespace (Argo
`CreateNamespace`), RBAC, datastores, and its own floci seeding (a local
Terraform stack the platform applies at bootstrap and the `tf-floci` pipeline
applies thereafter). Onboarding an app is its `Application` file(s) in
`envs/<env>/` plus one `sourceRepos` line — no platform code carries an app's name.

## Bootstrap vs. GitOps layer

| Layer | Lives in | How it's applied |
|-------|----------|------------------|
| **Bootstrap** | `install.sh`, `bootstrap/`, `clusters/`, `lib/` | imperatively, once, on the host |
| **GitOps** | `platform-config/`, `gitops-apps/` | pushed to Gitea, reconciled by Argo CD |

The bootstrap layer is the **only** sanctioned imperative surface. Everything that
runs on `dev`/`prod` is reconciled from Git.

## The external app

`todo-app` lives in its own repository (`modular-monolithic-app`), is mirrored to
Gitea, and is deployed only with `DEPLOY_APP=true` (default off). With it off, the
`todo-app` and `dependencies` Applications are omitted from the push, and the lab
stands up as a pure platform.
