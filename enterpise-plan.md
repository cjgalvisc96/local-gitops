# Enterprise Readiness Plan — `local-gitops` Platform (AWS Production)

**Goal:** take this platform from the local lab it is today to a hardened
**production deployment on a real AWS account**. The target is full enterprise
AWS: managed **EKS**, **Cognito** identity, **Secrets Manager/KMS**, **ECR**
supply chain, **CloudFront + WAF + ACM** edge, the **CloudTrail/Config/Security
Hub/GuardDuty** security baseline, **Aurora + ElastiCache** data, **CloudWatch +
SNS/SES** observability, a **multi-AZ VPC**, and **Organizations/SCP** governance.

`local-gitops` owns the clusters + GitOps control plane + observability; the app
(`modular-monolithic-app`, separate repo) deploys onto it. In production that
control plane runs on EKS; **floci/LocalStack is only the local inner-loop
emulator** for fast dev/CI (see §1). Everything in §2 onward describes the
**real-AWS production design** — no emulator limits apply.

> **Reconciled against the current repo.** Real paths are referenced throughout
> (`bootstrap/eks/*`, `gitops-apps/**`, `infra/terraform/lab/*`, `Taskfile.yml`,
> `install.sh`, `lib/common.sh`). The secrets path (External Secrets Operator in
> `gitops-apps/platform/base/secretstore.yaml`) is already AWS-shaped.

---

## 0. From lab to production — what changes

Today `task install` builds, via Terraform/Terragrunt (`infra/terragrunt/lab` →
`infra/terraform/lab`): a floci container (LocalStack `:4566`, `test/test`), a
kind `management` cluster (Gitea only), two k3s "EKS" clusters
(`floci-eks-todo-app-dev` `:6443` / `-prod` `:6444`) on the kind docker network,
and the Gitea Actions runner. `./install.sh` adds MetalLB + ingress-nginx +
Gitea + split-DNS; per-EKS, `task eks:bootstrap ENV=dev|prod` installs MetalLB +
ingress-nginx + Argo CD + the observability Argo `Application`
(`bootstrap/eks/observability-app.yaml`). In-cluster state is committed
manifests (`bootstrap/eks/*` via kubectl + `gitops-apps/observability/*` via
kustomize), currently all `emptyDir`.

**The production deltas:**

- The k3s "EKS" containers become **real Amazon EKS** clusters (managed node
  groups / Fargate) in a **multi-AZ VPC**. MetalLB → **AWS Load Balancer
  Controller** (ALB/NLB). Local-path PVCs → **EBS/EFS CSI**.
- floci endpoints (`http://floci:4566`, `test/test`) → **real AWS APIs via
  IRSA** — no static keys.
- Gitea/Argo stay as the GitOps control plane but front with **ACM + CloudFront
  + WAF + Route53**, not split-DNS + plain HTTP.
- The same `gitops-apps/**` kustomize tree and `bootstrap/eks/*` manifests
  deploy unchanged in shape; only endpoints, IAM, and storage backends differ.

The new infra is a **production Terragrunt stack** (`infra/terragrunt/prod/…`,
`infra/terraform/<module>/…`) alongside the existing `lab/` stack — VPC, EKS,
RDS, ElastiCache, Cognito, ECR, CloudFront/WAF, and the security baseline as
Terraform modules.

---

## 1. Local development (floci) — the inner loop only

floci/LocalStack is the **local dev/CI emulator**, not the deployment target. It
exists so a developer (and CI) can exercise the AWS-shaped wiring on a laptop
without an AWS account.

- Gated by **`var.floci = true`** in the Terraform lab stack
  (`infra/terraform/lab/variables.tf`). When set, the stack provisions the floci
  container and points workloads at `:4566` with `test/test`.
- floci **gates off** the services LocalStack-community can't run —
  **Cognito, WAF, GuardDuty, Config, Aurora, ElastiCache** — and substitutes:
  - **dev-auth**: the app runs in DEBUG mode trusting an `x-dev-tenant` header
    in place of the Cognito `tenant_id` claim;
  - **in-cluster Postgres + Redis** in place of Aurora + ElastiCache;
  - **self-signed issuer** in place of ACM/PCA.
- It exercises for real (so the IaC is identical to prod minus the endpoint):
  S3, ECR, Secrets Manager, SSM, KMS, SNS/SQS, EventBridge, CloudWatch,
  IAM/STS.

With `var.floci = false` the same modules target a real AWS account and every
gated service comes online. **Everything from §2 onward is the real-AWS
production design.**

---

## 2. Foundation — VPC, IAM/IRSA, KMS, EKS

Build the account and cluster baseline first; everything else trusts it.

### 2.1 Network — multi-AZ VPC
- **VPC across ≥3 AZs**: public subnets (ALB/NAT only), **private subnets** for
  nodes and data, isolated subnets for RDS/ElastiCache.
- **NAT gateways** per AZ; **VPC Flow Logs** to CloudWatch/S3.
- **PrivateLink / VPC endpoints** for S3, ECR (api+dkr), Secrets Manager, SSM,
  KMS, STS, CloudWatch — keep AWS API traffic off the internet.
- **Security Groups** as the L3/L4 boundary; **NetworkPolicy** (Cilium or
  Calico) for pod-level east-west control inside the cluster.

### 2.2 IAM + IRSA
- **One scoped IAM role per workload**, bound via **IRSA** (EKS OIDC provider):
  `api` pod, `ai` pod (`bedrock:InvokeModel` on specific model ARNs), DB-init
  Job (DDL + secret read, no data access), EventBridge publisher (publish-only),
  `external-secrets` (read Secrets Manager/SSM + `kms:Decrypt`),
  AWS LB Controller, EBS/EFS CSI, cluster-autoscaler. **No shared or
  account-wide role.**
- **IAM Access Analyzer** on; permissions boundaries on human roles.

### 2.3 KMS
- **Customer-managed CMKs** per trust boundary (secrets, RDS, EBS, S3, logs)
  with **automatic rotation** and tight key policies. Envelope-encrypt
  everything; no AWS-managed default keys for regulated data.

### 2.4 EKS
- **Amazon EKS** per environment (dev/prod), **private API endpoint**, managed
  node groups (and/or **Fargate** for system workloads), control-plane logging
  to CloudWatch.
- **Argo CD on EKS** as the GitOps engine (replaces the per-k3s Argo from
  `task eks:install-argo`); the `bootstrap/eks/*` manifests and
  `gitops-apps/**` overlays reconcile unchanged.
- Add-ons via IRSA: **AWS Load Balancer Controller**, **EBS/EFS CSI**,
  **external-dns** (Route53), **cluster-autoscaler/Karpenter**.

---

## 3. Identity — Amazon Cognito

- **Cognito user pool** per environment with **app clients** for the
  application, Argo CD, and Grafana; **hosted UI** or OIDC federation to a
  corporate IdP.
- **Groups → roles** (`platform-admins`, `dev-users`, `prod-users`) surfaced as
  a `cognito:groups` claim; the pool also emits the **`tenant_id`** claim that
  drives tenancy.
- **MFA enforced** + **advanced security** (compromised-credential and
  adaptive-risk detection); short token lifetimes; refresh rotation.
- Argo CD / Grafana use Cognito OIDC; group claims map to RBAC
  (`gitops-apps/platform/base/rbac.yaml`, Argo `appprojects`/RBAC). Drop
  anonymous Viewer in `gitops-apps/observability/base/grafana.yaml`.
- **Tenancy stays RLS, not app-layer filtering:** Cognito `tenant_id` claim →
  `get_request_context` → UoW `set_config('app.tenant_id', …, local)` →
  PostgreSQL RLS. (Local dev substitutes the `x-dev-tenant` header for the
  claim — §1.)

---

## 4. Secrets & config — Secrets Manager + SSM + KMS via ESO

The repo already runs **External Secrets Operator** with the AWS provider
(`gitops-apps/platform/base/secretstore.yaml`). Promote it to production:

- Swap the static `floci-aws-creds` (`test/test`) for the `external-secrets`
  **IRSA** role — the `ClusterSecretStore` spec is otherwise unchanged.
- **Secrets Manager** for rotated credentials (DB users, API keys) with
  **automatic rotation** (Lambda rotators for Aurora); **SSM Parameter Store**
  for plain config. All **KMS-encrypted** (§2.3).
- Purge every hardcoded credential from Git (Gitea/Grafana/DB); ESO materializes
  them as K8s `Secret`s at runtime. Bootstrap-only secrets via **SOPS + KMS**.

---

## 5. Supply chain — ECR + Trivy + cosign + SBOM

`trivy` is already pinned (`mise.toml`); `task eks:trivy-scan` already scans.

- **ECR** repositories with **scan-on-push** and **immutable tags**; lifecycle
  policies; cross-account replication for prod if needed.
- Image flow: **build → push to ECR → deploy by digest** (replaces
  `docker build → k3s import`). Pull via IRSA/node role, no static creds.
- **Trivy** (SBOM via Syft + CVE gate, fail high/critical) and **cosign**
  signing in the Gitea Actions pipeline; **Kyverno `verifyImages`** (§7) rejects
  unsigned/untrusted images at admission. Pin every image by **digest**.

---

## 6. Edge, TLS & WAF

- **ACM** certificates (DNS-validated) for all public hostnames; **Route53** as
  authoritative DNS + health checks (replaces local split-DNS).
- **CloudFront** in front of the app/UI with **AWS WAF** (managed rule groups +
  rate limiting + geo/IP rules); origin is the **ALB** via the AWS LB Controller
  ingress.
- Flip the plain-HTTP shortcuts: TLS + ACM on
  `bootstrap/eks/argocd-ingress.yaml`, `bootstrap/gitea/ingress.yaml`,
  `gitops-apps/observability/overlays/{dev,prod}/ingress.yaml`; HTTPS redirect
  on. **ACM Private CA** for internal mTLS where required.

---

## 7. Security & audit baseline

Account-wide guardrails, enforced via Organizations:

- **CloudTrail org trail** (all regions, log-file validation) → S3 + CloudWatch
  Logs.
- **AWS Config** (recorder + conformance packs) and **Security Hub** (CIS / AWS
  Foundational standards) aggregated org-wide.
- **GuardDuty** (incl. EKS audit-log + runtime monitoring, S3, malware).
- **VPC Flow Logs** (§2.1) and **IAM Access Analyzer** (§2.2).
- **Kyverno** in-cluster (admission policy) complements **AWS Config rules**:
  no `:latest`, require requests/limits, non-root + drop ALL caps +
  `readOnlyRootFilesystem`, require ECR images, `verifyImages`, forbid
  `emptyDir` for stateful workloads. **Pod Security Admission `restricted`** on
  app/observability namespaces (`gitops-apps/platform/base/namespaces.yaml`).
  **NetworkPolicy** (Cilium/Calico) default-deny complements Security Groups.

---

## 8. Data — Aurora + ElastiCache

- **Aurora PostgreSQL** (Multi-AZ, ≥2 instances), **storage encrypted (KMS)**,
  **PITR**, automated + manual snapshots, **IAM database auth** /
  Secrets-Manager-rotated app credentials. Replaces the in-cluster
  `emptyDir` Postgres. **RLS policies** (`migrations/policies/*.sql`) are the
  tenant-isolation boundary — unchanged.
- **ElastiCache (Redis)** Multi-AZ with automatic failover, encryption
  in-transit + at-rest, for session/cache workloads.
- Subnets isolated (§2.1); access only from node Security Groups.

---

## 9. Observability & alerting

The three pillars exist (`gitops-apps/observability/base/*`) but are `emptyDir`.
Make them durable and AWS-native:

- **S3-backed Loki/Tempo**: switch `loki.yaml` `storage.filesystem` → S3 and
  `tempo.yaml` storage → S3 (via IRSA). Lengthen retention past 24h/1h.
- **CloudWatch** Logs/Metrics + **dashboards** + **Container Insights**;
  optionally **Amazon Managed Prometheus (AMP)** + **Amazon Managed Grafana**
  for managed long-term metrics, or persistent self-hosted Prometheus
  (`gitops-apps/observability/base/prometheus.yaml`) with a PVC + CloudWatch
  remote-write.
- **Alerting**: **CloudWatch Alarms → SNS → SES** (and/or PagerDuty/Slack via
  SNS). Alarms for SLO burn-rate, Argo sync health, cert expiry, ESO sync
  failures, Kyverno denials, RDS/ElastiCache health, GuardDuty findings.
- **Audit/log retention** to S3 with lifecycle → Glacier.

---

## 10. Backup & DR

- **AWS Backup** plans covering Aurora, EBS/EFS, and DynamoDB into a
  **KMS-encrypted backup vault**; cross-region copy for prod; vault-lock for
  immutability.
- **S3** for Loki/Tempo blocks (§9), GitOps state, and exports — versioned,
  lifecycle-managed.
- Rehearse restore after a deliberate wipe; track **RPO/RTO**. Argo controllers
  are reconstructable from Git — back up *data*, not controllers.

---

## 11. CI/CD & promotion

- **Gitea Actions** gate on every PR to `gitops-apps`/app: `kustomize build` →
  `kubeconform` → `kyverno test`/`conftest` → Trivy → diff preview (formalizes
  the existing `task validate` / `task validate:kustomize`). Branch protection +
  CODEOWNERS.
- **Argo Rollouts** in dev/prod for canary/blue-green with Prometheus/CloudWatch
  analysis + auto-rollback.
- **Promotion DEV→PROD** stays PR-driven (existing `promote`/`ship` tasks) but
  bumps an **ECR digest** with a required approver — never a floating tag.

---

## 12. Cost & governance

- **AWS Organizations** with **SCPs** (deny risky regions/services, enforce
  encryption + tagging); per-team **IAM** with permissions boundaries.
- **Cost Explorer + Budgets** with alerts; **mandatory tagging** policy
  (team/env/cost-center) enforced via Config + SCP.
- **ResourceQuota + LimitRange** per namespace; scoped Argo AppProjects
  (tighten the `*/*` wildcards in `bootstrap/eks/appprojects.yaml`).

---

## 13. Phased roadmap (execute top to bottom)

Each phase ends green before the next begins.

| Phase | Adds | Key AWS services | Validate |
|------|------|------------------|----------|
| **P0. Foundation** | Multi-AZ VPC, IAM/IRSA, KMS CMKs, EKS + Argo, LB Controller, CSI | VPC, IAM, KMS, EKS, ECR endpoints | nodes Ready; IRSA assumes role; ALB provisions |
| **P1. Identity** | Cognito pool/clients/groups, MFA, advanced security; Argo/Grafana OIDC | Cognito | group claim drives RBAC; MFA enforced |
| **P2. Secrets** | ESO → Secrets Manager + SSM via IRSA, KMS, rotation; purge plaintext | Secrets Mgr, SSM, KMS | no creds in Git; ExternalSecrets sync; rotation works |
| **P3. Supply chain** | ECR scan-on-push + immutable tags, Trivy, cosign, SBOM | ECR | unsigned image rejected; CI fails on critical CVE |
| **P4. Edge/TLS/WAF** | ACM, Route53, CloudFront + WAF, ALB ingress | ACM, Route53, CloudFront, WAF | HTTPS green; WAF blocks rule hits |
| **P5. Security baseline** | CloudTrail org trail, Config, Security Hub, GuardDuty, Flow Logs, Access Analyzer; Kyverno + NetworkPolicy | CloudTrail, Config, Security Hub, GuardDuty | Security Hub score; findings route to SNS |
| **P6. Data** | Aurora Multi-AZ + PITR, ElastiCache, isolated subnets | Aurora, ElastiCache | failover test; PITR restore; RLS isolation holds |
| **P7. Observability** | S3-backed Loki/Tempo, CloudWatch + (AMP/AMG), Alarms→SNS→SES | CloudWatch, S3, SNS, SES | restart keeps logs/traces; alarm fires |
| **P8. Backup/DR** | AWS Backup vault, cross-region copy, restore drill | AWS Backup, S3 | wipe → restore; RPO/RTO tracked |
| **P9. CI/CD & cost** | Actions gates, Argo Rollouts, SCPs, Budgets, quotas, tagging | Organizations, Cost Explorer | PR gate blocks; canary rolls back; budget alert |

---

## 14. Repo changes summary (real paths)

**Infra (new production stack alongside `lab/`):**
- `infra/terragrunt/prod/…` + `infra/terraform/<module>/…` — VPC, EKS, IAM/IRSA,
  KMS, ECR, Cognito, ACM/CloudFront/WAF/Route53, Aurora, ElastiCache, AWS
  Backup, CloudTrail/Config/Security Hub/GuardDuty modules.
- `infra/terraform/lab/variables.tf` — `var.floci` gate (true=local emulator,
  false=real AWS).
- `lib/common.sh` / `install.sh` / `Taskfile.yml` — IRSA-based bootstrap (no
  static keys); ECR push path; S3 backup targets; keep `install`,
  `eks:bootstrap`, `gitea:ship`.

**Bootstrap (per-EKS, via kubectl):**
- `bootstrap/eks/argocd-ingress.yaml`, `bootstrap/gitea/ingress.yaml` — ACM TLS
  + ALB + redirect.
- `bootstrap/eks/appprojects.yaml` — scope `sourceRepos`/whitelists off `*`.
- `bootstrap/ingress-nginx/values.yaml` — replaced/augmented by AWS LB
  Controller; webhooks on.
- new `bootstrap/eks/kyverno-app.yaml` alongside `observability-app.yaml`.

**GitOps apps (kustomize):**
- `gitops-apps/platform/base/secretstore.yaml` — IRSA + Secrets Manager store.
- `gitops-apps/platform/base/{namespaces,rbac}.yaml` — PSA `restricted`, scoped
  RBAC, ResourceQuota/LimitRange.
- `gitops-apps/observability/base/{loki,tempo}.yaml` — S3 backend + retention.
- `gitops-apps/observability/base/prometheus.yaml` — PVC + CloudWatch/AMP.
- `gitops-apps/observability/base/grafana.yaml` — Cognito OIDC, no anon, secret
  from Secrets Manager.

---

## 15. First concrete step

P0 is the unblock-everything step:
1. Stand up the **production Terragrunt stack**: multi-AZ VPC, EKS with the OIDC
   provider, KMS CMKs, and the core **IRSA roles** (external-secrets, LB
   Controller, CSI).
2. Install **Argo CD on EKS** and point it at `gitops-apps` — the existing
   `bootstrap/eks/*` + overlays reconcile unchanged.
3. Verify IRSA (a pod assumes its role and reads a test SSM parameter), the ALB
   provisions from an ingress, and the EBS CSI binds a PVC.

A fast early win that needs little: **switch `loki.yaml` / `tempo.yaml` to S3
(via IRSA)** so observability survives restarts and sets up the Kyverno
"no emptyDir for stateful" rule in P5.

Once P0 is solid, the remaining phases are additive Terraform modules + Argo
`Application`s the cluster reconciles — the same GitOps workflow the lab already
demonstrates, now against real AWS. Local development continues on **floci**
(§1) as the inner loop, with `var.floci=true` gating the services LocalStack
can't run.
