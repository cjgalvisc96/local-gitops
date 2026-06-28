# Repository layout

```
.
├── Taskfile.yml          workflow entry points (task install, eks:*, validate, …)
├── install.sh            management-cluster Kubernetes layer (Gitea + DNS)
├── prune.sh              host cleanup (DNS, /etc/hosts, mise activation)
├── lib/common.sh         pinned versions, network derivation, shared helpers
├── mise.toml             pinned CLI toolchain (one source of truth)
├── infra/                infrastructure as code (Terraform/Terragrunt)
│   ├── terraform/lab/    floci + kind management + 2 floci-EKS clusters + runner
│   └── terragrunt/lab/   Terragrunt wrapper (local state under the repo)
├── bootstrap/            imperative install assets (committed manifests)
│   ├── eks/              per-EKS Argo CD: appprojects, ingress, MetalLB pool, observability app
│   ├── gitea/            Gitea values, ingress, pinned LoadBalancer, runner config
│   └── ingress-nginx/    ingress-nginx values
├── gitops-apps/          Kustomize manifests Argo CD reconciles
│   ├── platform/         namespaces, ConfigMap, RBAC, ClusterSecretStore
│   └── observability/    OTel collector/agent, Prometheus, Loki, Tempo, Grafana
└── docs/                 this documentation (MkDocs)
```

## Conventions

- **Base + per-env overlays** (Kustomize). Env-specific values live in the
  overlay, never hard-coded in the base.
- **One app per namespace.** Ingress hosts are
  `gitea|argo|grafana|<app>.<env>.local`.
- **Pinned everything.** Tool versions in `mise.toml`; chart/image versions in
  `lib/common.sh` and the manifests. No floating `latest` in the GitOps layer.
- **Self-explanatory code.** Clear names and structure over comments; the rare
  comment records a non-obvious *why* (a workaround or a load-bearing marker
  string), never a *what*.

## `gitops-apps` stacks

| Stack | Contains |
|-------|----------|
| `platform` | namespaces, ConfigMap, RBAC, `ClusterSecretStore` |
| `observability` | OTel collector + agent, Prometheus, Loki, Tempo, kube-state-metrics, Grafana |

Each is a Kustomize `base/` with `overlays/dev` and `overlays/prod`. The app's own
datastores (`dependencies`) live in the app's repo, not here.
