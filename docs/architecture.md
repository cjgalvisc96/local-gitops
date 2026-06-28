# Architecture

## The platform owns the clusters

This repo is the **platform**. It owns the clusters, the GitOps control plane and
observability. **Apps deploy onto it** — they no longer create or bootstrap any
cluster. There are two repos in the picture:

- **`local-gitops`** (this repo) — the platform: clusters + Argo CD + observability.
- **`modular-monolithic-app`** — an example app that deploys *onto* the platform,
  from its own repository.

## Three clusters

| Cluster | Kind | Runs |
|---------|------|------|
| `management` | kind (one container) | Gitea (the in-cluster Git server) — and only Gitea |
| `dev` | floci-EKS (`floci-eks-todo-app-dev`, k3s, host API `:6443`) | its **own** Argo CD, observability, the dev app |
| `prod` | floci-EKS (`floci-eks-todo-app-prod`, k3s, host API `:6444`) | its **own** Argo CD, observability, the prod app |

The two workload clusters are plain **k3s docker containers** (traefik + servicelb
disabled) that emulate EKS on floci. They are attached to the kind docker network
so MetalLB can advertise their LB IPs to the host and to Gitea. There is **no
central Argo CD** — each workload cluster reconciles itself.

```
                 ┌──────────────┐
                 │  management  │   Gitea (git server) — KIND
                 │   cluster    │   the GitOps repos live here
                 └──────┬───────┘
            clone over pinned LB IP (<prefix>.255.209)
        ┌───────────────┴────────────────┐
        ▼                                 ▼
 ┌──────────────┐                  ┌──────────────┐
 │ dev cluster  │   floci-EKS      │ prod cluster │   floci-EKS
 │  Argo CD     │   (k3s, .230)    │  Argo CD     │   (k3s, .240)
 │  observability                  │  observability
 │  + app       │                  │  + app       │
 └──────────────┘                  └──────────────┘
```

## What stands up, and when

`task install` builds the whole lab, in order — the platform brings up Argo CD and
Grafana on **both** workload clusters **before any app is deployed**:

1. **Infra** (Terraform/Terragrunt, `infra/terragrunt/lab → infra/terraform/lab`):
   the `floci` container, the kind `management` cluster, the two floci-EKS k3s
   clusters, and — on a second apply, once Gitea issues a token — the Gitea Actions
   runner.
2. **Management Kubernetes layer** (`install.sh`, helm/kubectl): MetalLB +
   ingress-nginx + Gitea on the management cluster, seeds the Gitea `gitops` org and
   the `gitops-apps` repo, and wires DNS.
3. **Per-EKS bootstrap** (`task eks:bootstrap ENV=dev` and `ENV=prod`, no
   `APP_DIR`): into **each** floci-EKS cluster — a single-IP MetalLB pool (dev
   `.230`, prod `.240`) + ingress-nginx + Argo CD + an observability Argo
   `Application` synced from `gitops-apps/observability/overlays/<env>`.

The result: `argo.dev/prod.local` and `grafana.dev/prod.local` are **live (http)**
before any app exists.

## In-EKS GitOps, per environment

Each workload cluster runs its own Argo CD (insecure/HTTP), reached at
`argo.<env>.local`. At bootstrap the platform applies, into each cluster:

- the `dev` / `prod` **AppProjects** (`bootstrap/eks/appprojects.yaml`),
- the Argo CD ingress (`bootstrap/eks/argocd-ingress.yaml`),
- a repo-credential Secret for `gitops-apps`,
- the **observability** Argo `Application` (`bootstrap/eks/observability-app.yaml`),
  which syncs the Kustomize overlay `gitops-apps/observability/overlays/<env>`.

There are **no ApplicationSets or cluster generators**: each Argo CD can only reach
its own cluster, so a cross-cluster generator would not work. An app adds itself by
registering its **own** Argo `Application` manifests with the right cluster's Argo
CD (the app pipeline does this via the platform's `task eks:register-app`).

## Platform vs. app boundary

The **platform** owns generic primitives only: the clusters (kind + floci-EKS),
Argo CD, ingress, MetalLB, DNS, floci, Gitea, the Gitea Actions runner, and
observability. An **app** owns everything app-specific in its own repo — Helm chart
/ manifests, namespace (Argo `CreateNamespace`), RBAC, datastores, its Argo
`Application` manifests, and its own cloud resources on floci (**ECR, Secrets,
SQS/SNS, EventBridge, S3** — provisioned by the app's Terragrunt apply; EKS/VPC are
gated off on floci because the **platform** owns the cluster). No platform code
carries an app's name.

## Bootstrap vs. GitOps layer

| Layer | Lives in | How it's applied |
|-------|----------|------------------|
| **Infra** | `infra/terraform/lab`, `infra/terragrunt/lab` | Terraform/Terragrunt, on the host |
| **Bootstrap** | `install.sh`, `bootstrap/`, `lib/`, the `eks:*` tasks | imperatively, once, on the host |
| **GitOps** | `gitops-apps/` (Kustomize overlays) | pushed to Gitea, reconciled by Argo CD |

In-cluster objects are committed manifests applied via kubectl
(`bootstrap/eks/{metallb-pool,argocd-ingress,appprojects,observability-app}.yaml`)
plus the Kustomize overlays for observability. Only repo-credential Secrets and a
couple of patches are imperative. Everything that runs on `dev`/`prod` thereafter is
reconciled from Git.

## The external app

`todo-app` lives in its own repository (`modular-monolithic-app`) and deploys onto
the running platform — from the app repo, `task gitea:create-repo && task
gitea:ship` triggers its DEV (automatic) Gitea Actions pipeline (ci → terraform →
cd). The platform stands up empty of apps on purpose; with no app onboarded the lab
is a pure platform with Argo CD and Grafana already live on both clusters.
