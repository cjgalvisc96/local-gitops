# platform-config

The **GitOps control repository**. Argo CD's `root` Application watches this repo
and applies everything here to the management cluster:

```
projects/           AppProjects (env separation: dev / prod)
applicationsets/    ApplicationSets that fan workloads out to the dev & prod clusters
  apps.yaml             application instances (app1, app2) x (dev, prod)
  observability.yaml    OpenTelemetry + Prometheus + Grafana per env
  platform.yaml         namespaces / ConfigMap / RBAC / SecretStore per env
  external-secrets.yaml External Secrets Operator (Helm) per env
```

ApplicationSets use the **cluster generator** with `environment in (dev, prod)`,
so adding a workload cluster is just registering a labeled Argo cluster secret.
Manifests they reference live in the `gitops-apps` repo.
