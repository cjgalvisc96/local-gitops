# Observability

Everything flows through **OpenTelemetry**. Each workload cluster runs the full
signal pipeline and a Grafana wired to all three backends.

```
            pods / kubelet / kube-state-metrics
                        │
        ┌───────────────┼────────────────┐
        ▼ metrics       ▼ logs            ▼ traces
   OTel Collector   OTel agent        OTel Collector
   (scrape)         (filelog DS)      (OTLP receiver)
        │               │                  │
        ▼               ▼                  ▼
   Prometheus         Loki              Tempo
        └───────────────┴──────────────────┘
                        ▼
                     Grafana   (Prometheus + Loki + Tempo datasources)
```

## The three signals

| Signal | Path |
|--------|------|
| **Metrics** | OTel Collector scrapes pod annotations + kube-state-metrics + kubelet/cAdvisor → Prometheus |
| **Logs** | OTel agent DaemonSet tails container logs (filelog) → Loki via OTLP |
| **Traces** | apps push OTLP → OTel Collector → Tempo |

It is OTel end to end — there is no Promtail; logs are collected by the OTel agent.

## What's deployed

`gitops-apps/observability/base` contains: `otel-collector`, `otel-agent`,
`prometheus`, `loki`, `tempo`, `kube-state-metrics`, `grafana`. The `dev`/`prod`
overlays drop them into the `observability` namespace and add the ingress.

## Grafana

Reachable at `http://grafana.dev.local` and `http://grafana.prod.local`, with
three datasources provisioned (uids `prometheus`, `loki`, `tempo`).

Useful signals to watch:

- `kube_pod_status_phase` — pod health from kube-state-metrics.
- `container_memory_working_set_bytes` — memory from cAdvisor/kubelet.
- `http_requests_total` — app request rate (if the app exports it).
- Loki: `{k8s_namespace_name=~".+"}` — all container logs by namespace.
