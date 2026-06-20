# GitOps Enterprise Lab (2026) — Final Goal

A fully local, reproducible GitOps platform that demonstrates how modern organizations manage applications across multiple Kubernetes environments using Git as the source of truth.

The lab should be installable with a single command:

./install.sh

and provide a realistic experience of:

GitOps workflows
Multi-cluster Kubernetes operations
Environment promotion (DEV → PROD)
Continuous delivery with Argo CD
Application observability
Internal Git hosting
Platform engineering fundamentals

# Architecture
                    ┌─────────────┐
                    │    Gitea    │
                    │ Git Server  │
                    └──────┬──────┘
                           │
                           │ GitOps Repositories
                           ▼

                    ┌─────────────┐
                    │   Argo CD   │
                    │ Management  │
                    └──────┬──────┘
                           │
         ┌─────────────────┴─────────────────┐
         ▼                                   ▼

┌──────────────────────┐       ┌──────────────────────┐
│      DEV Cluster     │       │     PROD Cluster     │
├──────────────────────┤       ├──────────────────────┤
│ Applications         │       │ Applications         │
│ OpenTelemetry        │       │ OpenTelemetry        │
│ Grafana              │       │ Grafana              │
│ Argo Managed         │       │ Argo Managed         │
└──────────────────────┘       └──────────────────────┘

# Technology Stack
## Bootstrap Layer
Installed directly by install.sh:

kind
MetalLB
ingress-nginx
Gitea
Argo CD

# GitOps Layer
Installed and managed by Argo CD:

Applications
OpenTelemetry Collector
Grafana
Ingress resources
Environment-specific configuration

# Clusters
Three Kubernetes clusters:
management
dev
prod

## management
### Hosts:
Gitea
Argo CD

#### dev
Hosts:
Development applications
OpenTelemetry
Grafana

#### prod
Hosts:
Production applications
OpenTelemetry
Grafana

# Git Repositories
## Platform Repository
Infrastructure and cluster configuration.
platform-config/
Contains:
clusters/
applicationsets/
Application Repositories

## Application source code.
app1/
app2/
appN/

## GitOps Repository
Deployment manifests and Helm values.
gitops-apps/
dev/
prod/

# GitOps Workflow
Developer
    │
    ▼

Push Code

    │
    ▼

Gitea Repository

    │
    ▼

Update GitOps Manifest

    │
    ▼

Argo CD Sync

    │
    ▼

Deploy to DEV

    │
    ▼

Promote

    │
    ▼

Deploy to PROD

# Observability Workflow
Application
     │
     ▼

OpenTelemetry Collector

     │
     ▼

Prometheus Metrics

     │
     ▼

Grafana Dashboards

# DNS & Access
The platform should expose friendly environment-based URLs:

gitea.dev.local
argo.dev.local
argo.prod.local
grafana.dev.local
grafana.prod.local
app1.dev.local
app1.prod.local
appN.dev.local
appN.prod.local

These should be automatically configured during installation through a local DNS solution (e.g. CoreDNS or dnsmasq) backed by MetalLB and ingress-nginx, avoiding manual /etc/hosts changes.

# install.sh
0. Verify dependencies(Docker, Git, Curl).
1. Install missing tools if not exists(kubectl, kind, helm, k9s, argocd cli)
2. Create Clusters(management, dev, prod)
3. Install MetalLB
4. Install ingress-nginx
5. Install Gitea
6. Install Argo CD
7. Register dev cluster
8. Register prod cluster
9. Bootstrap root Application
10. Print URLs

# What the Lab Demonstrates

✅ Multi-cluster Kubernetes

✅ GitOps with Argo CD

✅ Self-hosted Git with Gitea

✅ DEV and PROD environment separation

✅ Application promotion workflows

✅ Real ingress and load balancers

✅ OpenTelemetry-based observability

✅ Grafana dashboards

✅ Repeatable local platform setup

✅ Enterprise platform engineering concepts

# Success Criteria

After running:

./install.sh

a user should be able to:

1. Open Gitea and browse repositories.
2. Access Argo CD and observe GitOps synchronization.
3. Deploy applications through Git changes only.
4. Promote an application from DEV to PROD.
5. Access applications through environment-specific URLs.
6. Observe metrics in Grafana.
7. Understand how a modern multi-cluster GitOps platform operates without requiring any cloud infrastructure.