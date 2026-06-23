# Repository layout

```
.
├── install.sh            bootstrap the whole lab (the only imperative surface)
├── prune.sh              exact inverse of install.sh
├── lib/common.sh         pinned versions, network derivation, shared helpers
├── mise.toml             pinned CLI toolchain (one source of truth)
├── Taskfile.yml          workflow entry points (task install, validate, …)
├── clusters/             kind cluster definitions (management, dev, prod)
├── bootstrap/            imperative install assets
│   ├── argocd/           Argo CD params, RBAC, ingresses, root apps (dev/prod)
│   ├── gitea/            Gitea values, ingress, pinned LoadBalancer, runner config
│   ├── ingress-nginx/    ingress-nginx values
│   └── dns/              local DNS wiring
├── platform-config/      GitOps control repo (app-of-apps)
│   └── envs/
│       ├── dev/          AppProject + one Application per stack (dev)
│       └── prod/         AppProject + one Application per stack (prod)
├── gitops-apps/          Kustomize manifests Argo CD reconciles
│   ├── platform/         namespaces, ConfigMap, RBAC, SecretStore
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
