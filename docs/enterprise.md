# Enterprise Readiness

The production target for this platform is a **full deployment on a real AWS account**. The kind +
floci lab in this repo is only the local inner-loop emulator (`var.floci=true`); it gates off the
AWS services LocalStack cannot run and substitutes dev-auth + in-cluster Postgres/Redis.

## Target AWS platform

| Pillar | AWS services |
|--------|--------------|
| Network & compute | Multi-AZ VPC (private/isolated subnets, NAT, Flow Logs, PrivateLink) + real EKS (managed node groups / Fargate) |
| GitOps control plane | Argo CD on EKS, AWS Load Balancer Controller, EBS/EFS CSI, IRSA |
| Identity | Amazon Cognito — user pool, app clients, groups → roles, MFA |
| Secrets & config | Secrets Manager + SSM + KMS (rotation), via External Secrets + IRSA |
| Registry & supply chain | ECR (scan-on-push, immutable tags) + Trivy + cosign + SBOM |
| Edge & TLS | ACM + CloudFront + AWS WAF + ALB, Route 53 |
| Audit & detection | CloudTrail (org trail) + AWS Config + Security Hub + GuardDuty + VPC Flow Logs + IAM Access Analyzer |
| Data | Aurora (Multi-AZ, PITR, KMS) + ElastiCache |
| Observability | CloudWatch logs/metrics/alarms → SNS → SES; S3-backed Loki/Tempo; optional AMP/AMG |
| Backup & DR | AWS Backup + S3 |
| Governance & cost | Organizations / SCPs, Cost Explorer / Budgets, tagging |

## Scope split

The **platform** (this repo) owns the cluster, the GitOps control plane, observability, and the
**account-level security baseline** (CloudTrail, GuardDuty, Security Hub, Config, Access Analyzer —
per-account singletons). Each **application** owns its own app-scoped resources (its ECR, secrets,
WAF, app IRSA roles) and deploys onto the platform's cluster.
