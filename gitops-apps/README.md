# gitops-apps

Deployment manifests (Kustomize) synced by Argo CD onto the **dev** and **prod**
clusters. Bases are environment-agnostic; overlays carry env-specific config.

```
apps/
  base/                 podinfo app (exposes Prometheus metrics)
  overlays/<env>/<app>/ namespace + ingress host + env config (app1, app2)
observability/
  base/                 OpenTelemetry Collector -> Prometheus -> Grafana
  overlays/<env>/       Grafana ingress host per env
platform/
  base/                 namespaces, shared ConfigMap, RBAC, floci SecretStore
  overlays/<env>/       ENVIRONMENT + per-env secret paths
```

Promotion DEV → PROD is a Git change to the matching `prod` overlay (e.g. bump
the image tag), which Argo CD then syncs.
