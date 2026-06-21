# Enterprise Readiness Plan — `local-gitops` (Full-Local Edition)

**Goal:** run the *entire* enterprise hardening stack with **zero cloud
dependencies**, on a single workstation, using **Keycloak** as the identity
provider. Every "cloud" item is replaced by an in-cluster open-source
equivalent and wired into the repo's existing app-of-apps GitOps model.

Hardware assumption: ~128 GB RAM available, so nothing here is trimmed for
footprint. Expect the full stack to consume ~40–70 GB RAM across the three
clusters when everything is running.

> **Reconciled against repo @ `0d7f67e` (2026-06-21).** See the delta note below.

---

## Δ Repo delta since last revision (what's already moved)

The repo has advanced on the **observability** and **developer-experience**
fronts. This plan is updated accordingly — those items are now marked *partially
done* rather than *to add*.

**Now present in the repo (good — credit where due):**
- **Logs:** `loki.yaml` + an **otel-agent** `DaemonSet` (`otel-agent.yaml`)
  tailing `/var/log/pods/*` and shipping to Loki via OTLP.
- **Traces:** `tempo.yaml` (OTLP receivers on 4317/4318).
- **Metrics breadth:** `kube-state-metrics.yaml` added alongside Prometheus.
- **Grafana wiring:** Loki **and** Tempo are now provisioned as datasources in
  `grafana.yaml` (with a logs panel) — the three-pillar correlation is in place.
- **Toolchain pinned:** `mise.toml` pins `kubectl/kind/helm/k9s/argocd/kustomize/
  awscli/task` **and `trivy`** — i.e. the supply-chain scanner is already on the
  bench. `Taskfile.yml` wraps `install`/`install:app`/etc. as `task` targets.

**Still exactly as before (this plan's core remains valid):**
- Argo still runs `server.insecure: "true"`; everything is plain HTTP.
- `secretstore.yaml` still uses the floci `aws`/ParameterStore provider with
  `test/test`; no Vault.
- Grafana still `admin/admin` with **anonymous Viewer enabled**.
- The new Loki/Tempo/otel-agent all use **`emptyDir`** (Loki retention 24h,
  Tempo 1h) — observability data is still ephemeral.
- No cert-manager / Keycloak / Vault / Harbor / MinIO / Cilium / Kyverno yet.

Net effect on the plan: **§10 (observability) drops from "build it" to "make it
durable + add alerting + long-term storage,"** and **§6 (supply chain) gets a
head start** because `trivy` is already pinned. Everything else is unchanged.

---

## 0. What stays, what's added

The existing architecture is kept verbatim: three `kind` clusters
(`management`, `dev`, `prod`), per-env Argo CD, Gitea on management, MetalLB
(`172.18.255.200–229` split by env), ingress-nginx, ESO, automated dnsmasq
split-DNS for `*.dev.local` / `*.prod.local`, and now an OTel→Prometheus/Loki/
Tempo→Grafana observability stack in dev/prod.

New platform components and where they run:

| Component | Role | Cluster(s) | Host | Status |
|-----------|------|-----------|------|--------|
| **cert-manager + trust-manager** | private CA, issue TLS, distribute CA bundle | all 3 | — | to add |
| **Keycloak** | OIDC IdP (SSO for everything) | management | `keycloak.dev.local` | to add |
| **Vault** | real secrets backend (replaces floci as canonical) | management | `vault.dev.local` | to add |
| **Harbor** | private registry + Trivy scanning + cosign | management | `harbor.dev.local` | to add |
| **MinIO** | S3-compatible store (Velero/Loki/Tempo/Thanos backend) | management | `minio.dev.local` | to add |
| **Cilium** | CNI with NetworkPolicy + Hubble (replaces kindnet) | all 3 | `hubble.dev.local` | to add |
| **Kyverno** | policy admission + image verification | dev, prod | — | to add |
| **Loki / Tempo** | logs / traces | dev, prod | — | **present (ephemeral)** |
| **kube-state-metrics** | cluster object metrics | dev, prod | — | **present** |
| **Alertmanager / Thanos** | alerts / long-term metrics | dev, prod | `*.{dev,prod}.local` | to add |
| **Mailpit** | local SMTP sink for Alertmanager/Keycloak email | management | `mail.dev.local` | to add |
| **Velero** | backup/restore to MinIO | all 3 | — | to add |
| **Argo Rollouts** | progressive delivery (canary/blue-green) | dev, prod | — | to add |
| **OpenCost** | cost visibility | dev, prod | `cost.{dev,prod}.local` | to add |

`floci` is retained but demoted: keep it as an optional "this is how it looks
against AWS SSM/ECR" demo path. The **canonical** secrets backend becomes Vault
and the **canonical** registry becomes Harbor.

---

## 1. The two things everything else depends on

Build these first, in this exact order — every later step trusts them.

### 1.1 Private CA + trust distribution (cert-manager + trust-manager)
This is the backbone. OIDC, mTLS, and registry pulls all fail until the CA is
trusted everywhere.

1. Install **cert-manager** in all three clusters (GitOps `Application`,
   sync-wave very early, e.g. `-10`).
2. Generate one **root CA** (a self-signed `ClusterIssuer` bootstraps an
   intermediate CA `Certificate`, which becomes the real `ClusterIssuer`).
3. Install **trust-manager** and create a `Bundle` that publishes the root CA
   public cert as a ConfigMap into every namespace.
4. Add the root CA to the **host browser trust store** so `https://*.dev.local`
   is green locally.
5. Add the root CA to the **kind node trust stores** (see §3.4) so the
   apiserver can validate Keycloak for OIDC.

Sketch — CA issuer:
```yaml
# gitops-apps/platform/base/ca-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: selfsigned-root }
spec: { selfSigned: {} }
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: gitops-root-ca, namespace: cert-manager }
spec:
  isCA: true
  commonName: gitops-local-root
  secretName: gitops-root-ca
  issuerRef: { name: selfsigned-root, kind: ClusterIssuer }
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: gitops-ca }      # <-- every Ingress references this
spec: { ca: { secretName: gitops-root-ca } }
```

### 1.2 Keycloak (SSO for the whole platform)
Runs on the management cluster (identity is control-plane infra, like Gitea).

- Deploy via the Keycloak Operator or Bitnami chart as a GitOps `Application`,
  exposed at `https://keycloak.dev.local` with a cert-manager cert (SAN must be
  `keycloak.dev.local` — this exact match matters for the K8s apiserver later).
- Back it with a persistent Postgres (CNPG, §8).
- Create one realm `gitops` with these OIDC clients:
  `argocd-dev`, `argocd-prod`, `grafana-dev`, `grafana-prod`, `gitea`,
  `kubernetes` (public, for kubectl/apiserver).
- Create groups matching the repo's existing Argo RBAC: `platform-admins`,
  `dev-users`, `prod-users`. These map straight onto
  `bootstrap/argocd/argocd-rbac.yaml` (`role:admin`, `role:dev`, `role:prod`).
- Point Keycloak SMTP at **Mailpit** so emails are catchable locally.

Once §1.1 and §1.2 are green, everything else is incremental.

---

## 2. TLS everywhere (replaces all plain HTTP)

Flip the repo's HTTP shortcuts:

- **Remove** `server.insecure: "true"` from
  `bootstrap/argocd/argocd-cmd-params.yaml`.
- Every Ingress (`bootstrap/gitea/ingress.yaml`,
  `bootstrap/argocd/ingress-*.yaml`,
  `gitops-apps/observability/overlays/*/ingress.yaml`): add a `tls:` block, the
  `cert-manager.io/cluster-issuer: gitops-ca` annotation, and switch
  `ssl-redirect` to `"true"`.
- Gitea: set `ROOT_URL: https://gitea.dev.local/`; register the repo in Argo
  with the CA bundle so cross-cluster clones over HTTPS validate. (Keep the
  pinned MetalLB IP `172.18.255.209` but front it with TLS, or switch Argo repo
  creds to SSH.)
- **East-west mTLS:** install **Linkerd** (lighter) or **Istio ambient** in
  dev/prod and mesh the app/observability/platform namespaces. This encrypts
  `http://prometheus:9090`, `http://loki:3100`, `http://tempo:3200`, DB
  connections, and ESO→Vault traffic that is cleartext today.

---

## 3. Identity wiring (Keycloak → each system)

### 3.1 Argo CD
In `argocd-cm` add `oidc.config` → `https://keycloak.dev.local/realms/gitops`,
client `argocd-dev`/`argocd-prod`, mount the CA bundle. Map Keycloak groups →
existing roles in `argocd-rbac-cm`:
```
g, platform-admins, role:admin
g, dev-users,       role:dev
g, prod-users,      role:prod
```
The `dev-user`/`prod-user` subjects that can't authenticate today become real,
group-driven logins.

### 3.2 Grafana
Replace the hardcoded `admin/admin` + **anonymous** (still enabled in
`grafana.yaml`) with:
```
GF_AUTH_ANONYMOUS_ENABLED=false
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_AUTH_URL/TOKEN_URL/API_URL=...keycloak.dev.local/realms/gitops...
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH=  # map groups -> Admin/Editor/Viewer
```
Admin password comes from Vault (§4), not the manifest. (Datasources for
Prometheus/Loki/Tempo are already provisioned — leave those as-is.)

### 3.3 Gitea
Add a Keycloak OAuth2 auth source (`gitea admin auth add-oauth`). Local admin
stays as break-glass only.

### 3.4 Kubernetes API server (advanced — the one fiddly step)
Optional: app-level SSO (3.1–3.3) gives the full demo; apiserver OIDC adds
`kubectl`-as-Keycloak-user. Requires `clusters/*.yaml` changes:
- **Mount the root CA** into the control-plane node via `extraMounts`.
- **Resolve `keycloak.dev.local`** from inside the node (hosts entry / point at
  dnsmasq); issuer URL must be reachable and its cert SAN = `keycloak.dev.local`.
- apiserver `extraArgs` via `kubeadmConfigPatches`:
```yaml
# clusters/dev.yaml (excerpt)
kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        oidc-issuer-url: https://keycloak.dev.local/realms/gitops
        oidc-client-id: kubernetes
        oidc-ca-file: /etc/kubernetes/pki/keycloak-ca.crt
        oidc-username-claim: email
        oidc-groups-claim: groups
      extraVolumes:
        - { name: kcca, hostPath: /etc/kubernetes/pki/keycloak-ca.crt, mountPath: /etc/kubernetes/pki/keycloak-ca.crt, readOnly: true, pathType: File }
nodes:
  - role: control-plane
    extraMounts:
      - { hostPath: ./.ca/root.crt, containerPath: /etc/kubernetes/pki/keycloak-ca.crt }
```
Bind groups to K8s RBAC (`ClusterRoleBinding` subject `kind: Group`).
**Fallback:** a small **Dex** per cluster as an OIDC shim, or skip apiserver
OIDC and keep group-based RBAC bound to ServiceAccounts.

---

## 4. Secrets — out of Git, into Vault (local IAM)

### 4.1 Stand up Vault (management cluster)
- Deploy Vault as a GitOps `Application` at `https://vault.dev.local`, persistent
  storage, unseal via transit or manual for the lab.
- Enable **KV v2** and seed the values currently hardcoded (Gitea admin, Grafana
  admin, Postgres `todo/todo`, app DB creds).
- Enable **Kubernetes auth**, one role per cluster — the local equivalent of
  cloud workload identity (IRSA). ServiceAccount tokens authenticate; **no
  static keys**.

### 4.2 Repoint ESO
The repo already runs ESO + a `ClusterSecretStore`
(`gitops-apps/platform/base/secretstore.yaml`, still floci/`aws`/ParameterStore).
Change the provider to **Vault** using Kubernetes auth. The static
`floci-aws-creds` (`test/test`) secret goes away.

### 4.3 Kill plaintext-in-Git
- Remove credentials from `lib/common.sh`, `grafana.yaml`, `postgres.yaml`.
- For bootstrap secrets that must live in Git, encrypt with **SOPS + age**
  (local keypair, no KMS) or **Sealed Secrets**.
- Generate Gitea/Grafana/Postgres admin creds at install time straight into
  Vault; print nothing sensitive to stdout.

---

## 5. Policy, Pod Security & Network

### 5.1 Kyverno (dev, prod)
GitOps `Application`. Start `Audit`, then `Enforce`: disallow `:latest`, require
requests/limits, require non-root + drop ALL caps + readOnlyRootFilesystem,
require images from `harbor.dev.local`, `verifyImages` against the cosign key
(§6), forbid `emptyDir` for stateful workloads — **including Loki/Tempo once
they're on PVCs (§8)**.

### 5.2 Pod Security Admission
Label namespaces in `gitops-apps/platform/base/namespaces.yaml`
`pod-security.kubernetes.io/enforce: restricted`. Add `securityContext` to
Grafana, Postgres, Keycloak, Loki, Tempo, otel-agent, etc.

### 5.3 NetworkPolicies via Cilium
Recreate clusters with `disableDefaultCNI: true` and install **Cilium**
(bootstrap imperatively right after cluster-create, like MetalLB). Then:
default-deny per namespace; allow ingress→app, app→postgres/redis, observability
scraping (incl. otel-agent→Loki, app→Tempo), ESO→Vault, registry pulls. **Hubble**
UI at `hubble.dev.local`. Tighten the wildcard AppProjects (`*/*` in
`platform-config/envs/*/project.yaml`). Re-enable ingress-nginx admission
webhooks and **drop** `allow-snippet-annotations: "true"` in
`bootstrap/ingress-nginx/values.yaml`.

---

## 6. Supply chain — Harbor + cosign (local)

> Head start: **`trivy` is already pinned in `mise.toml`** — wire it into CI now.

- **Harbor** on management at `https://harbor.dev.local` (built-in Trivy
  scanning). Replaces the floci ECR path as canonical.
- Change image flow (`install.sh` step 7 / `task install`): instead of
  `docker build → kind load`, do `build → push to harbor.dev.local → cluster
  pulls by digest`. Harbor pull creds via Vault/ESO.
- **cosign**: sign images in CI; public key in Vault; Kyverno `verifyImages`
  (§5.1) rejects unsigned/untrusted images at admission.
- **SBOMs** (Syft) + fail CI on high/critical CVEs (Trivy/Grype — trivy already
  available). Pin all images by digest; no floating tags (incl. replacing
  `floci/floci:latest`).

---

## 7. CI/CD & promotion (local)

- **Gitea Actions** + an `act_runner`. On every PR to
  `platform-config`/`gitops-apps`: `kustomize build` → `kubeconform` →
  `conftest`(OPA) / `kyverno test` → diff preview. (`kustomize` and `trivy` are
  pinned in `mise.toml`; reuse the same versions in CI.) This enforces the
  existing `validate-manifests` skill / `task`-driven checks as a real gate.
- Branch protection + CODEOWNERS on both GitOps repos.
- **Argo Rollouts** in dev/prod for canary/blue-green with analysis (query
  Prometheus) + auto-rollback.
- Promotion DEV→PROD becomes a PR that bumps the **prod image digest** with a
  required approver — replacing today's manual edits. Pin prod to a SHA, not
  `HEAD`. (Consider adding `task promote ENV=prod` wrapping the existing
  `/promote` skill.)

---

## 8. Reliability, durability & HA (simulated locally)

- Recreate `kind` clusters as **multi-node** to demonstrate anti-affinity,
  PodDisruptionBudgets, HA scheduling. (Fault domains simulated — one host.)
- **Persistent storage:** kind ships a local-path provisioner. Replace every
  `emptyDir` / `persistence: false` with PVCs — now explicitly including the
  **new observability components**: `loki.yaml`, `tempo.yaml`, and the
  otel-agent file-storage are all `emptyDir` today, so logs/traces vanish on
  restart. Also: Gitea, Postgres, Grafana, Keycloak, Vault, Harbor, MinIO,
  Prometheus.
- **Postgres:** **CloudNativePG** with replicas + PITR instead of the single
  `emptyDir` Postgres in `gitops-apps/dependencies/base/postgres.yaml`.
- **Gitea:** external CNPG Postgres + PVCs + ≥2 replicas (drop SQLite).
- **Argo CD:** HA mode (redis-ha, multiple controllers).

## 9. Backup & DR (Velero → MinIO)

- **MinIO** on management as the S3 endpoint for everything.
- **Velero** per cluster, backing up namespaces + PVs to MinIO on a schedule.
- CNPG continuous backup + PITR to MinIO.
- Rehearse restore after a deliberate wipe; track RPO/RTO. Back up the Vault
  unseal keys and bootstrap secrets (Argo is reconstructable from Git).

## 10. Observability — finish what's started (all local)

The three pillars now exist in the repo (Prometheus + Loki + Tempo + otel
collector/agent + kube-state-metrics, all surfaced in Grafana). What's left to
make it production-shaped:

- **Persistence (highest priority):** Loki (`emptyDir`, 24h), Tempo (`emptyDir`,
  1h), and otel-agent file-storage are ephemeral — move to PVCs (§8) and
  lengthen retention. For scale-out + long-term, back Loki/Tempo/Thanos with
  **MinIO** (§9) instead of local filesystem.
- **Alerting (missing entirely):** add **Alertmanager** + rules →
  **Mailpit** (SMTP) or a webhook. Add SLO/burn-rate alerts and platform alerts:
  Argo sync health, **cert expiry**, ESO/Vault failures, Kyverno denials, Loki
  ingestion errors.
- **Long-term metrics:** **Thanos** (or Mimir) on MinIO; persistent Prometheus.
- **Mesh/exemplars:** once mTLS (§2) is in, enable trace exemplars so Grafana
  jumps Prometheus → Tempo → Loki for a request. (Tempo OTLP is already on
  4317/4318, so app instrumentation can point straight at it.)

## 11. Multi-tenancy & governance

- `ResourceQuota` + `LimitRange` per namespace (none today — and the new obs
  components make this more pressing).
- Per-team AppProjects with scoped repos/destinations.
- **OpenCost** at `cost.{dev,prod}.local`.
- API server + Argo audit logs shipped to **Loki** (already running).

---

## 12. Phased install order (execute top to bottom)

Each phase ends green before the next begins.

| Phase | Adds | Validate |
|------|------|----------|
| **P0. Foundation** | Cilium (replaces kindnet), cert-manager + trust-manager, **private CA trusted on host + nodes** | `https://` green; CA bundle ConfigMap in all namespaces |
| **P1. Identity** | **Keycloak** + realm/clients/groups; Mailpit | log into Keycloak; OIDC discovery URL over trusted TLS |
| **P2. TLS cutover** | flip all Ingresses to TLS; remove Argo `insecure`; mesh mTLS | every UI HTTPS; Argo healthy without `insecure` |
| **P3. SSO** | wire Argo / Grafana / Gitea to Keycloak (apiserver OIDC optional) | group-based login; anonymous Grafana gone |
| **P4. Secrets** | Vault + k8s auth; repoint ESO; SOPS/Sealed; purge plaintext | no creds in Git; ExternalSecrets sync from Vault |
| **P5. Guardrails** | Kyverno (audit→enforce), PSA `restricted`, default-deny NetworkPolicies, scope AppProjects, nginx webhooks on | violations blocked; default-deny holds |
| **P6. Supply chain** | Harbor + Trivy + cosign; build→push→verify; SBOMs | unsigned image rejected at admission |
| **P7. CI/CD** | Gitea Actions gates, branch protection, Argo Rollouts, digest-pinned promotion | PR fails on bad manifest; canary + auto-rollback |
| **P8. Durability/DR** | multi-node, PVCs everywhere (**incl. Loki/Tempo**), CNPG, Argo HA, MinIO, Velero | kill a pod → no data loss; restart keeps logs/traces; Velero restore works |
| **P9. Operate** | **Alertmanager + Thanos** (Loki/Tempo already live), quotas, OpenCost, audit→Loki | alert fires to Mailpit; metrics+logs+traces correlate across restart |

---

## 13. Repo changes summary

**New under `gitops-apps/platform/`:** `ca-issuer.yaml`, `keycloak/`, `vault/`,
`harbor/`, `minio/`, `cilium/` (or bootstrapped), `kyverno/`, `velero/`,
`mailpit/`, `trust-manager-bundle.yaml`.

**New under `gitops-apps/observability/`:** `alertmanager/`, `thanos/`,
`opencost/`. *(Loki, Tempo, otel-agent, kube-state-metrics already exist.)*

**New `Application` manifests** in `platform-config/envs/{dev,prod}/` for each
of the above (sync-waves: CNI/cert-manager earliest, then CA, Keycloak, Vault,
the rest).

**Modified existing files:**
- `clusters/*.yaml` → `disableDefaultCNI: true`, multi-node, apiserver OIDC
  `extraArgs` + CA `extraMounts` (P0/P3/P8).
- `bootstrap/argocd/argocd-cmd-params.yaml` → drop `server.insecure`.
- `bootstrap/argocd/ingress-*.yaml`, `bootstrap/gitea/ingress.yaml`,
  `gitops-apps/observability/overlays/*/ingress.yaml` → TLS + `gitops-ca` + redirect.
- `bootstrap/ingress-nginx/values.yaml` → webhooks on, drop snippet annotations.
- `platform-config/envs/*/project.yaml` → scope `sourceRepos`/whitelists.
- `gitops-apps/platform/base/secretstore.yaml` → Vault provider (k8s auth).
- `gitops-apps/platform/base/{namespaces,rbac}.yaml` → PSA labels, scoped RBAC.
- `gitops-apps/observability/base/grafana.yaml` → OIDC, no anon, secret from
  Vault (keep existing Prometheus/Loki/Tempo datasources).
- **`gitops-apps/observability/base/{loki,tempo,otel-agent}.yaml` → PVCs +
  longer retention (and MinIO backend for scale-out).** *(new in this revision)*
- `gitops-apps/dependencies/base/postgres.yaml` → CNPG cluster, PVC.
- `lib/common.sh` / `install.sh` / `Taskfile.yml` → CA gen + node trust, Cilium
  bootstrap, Harbor push path, Vault seeding, no plaintext creds; add
  `task` targets for the new phases.

---

## 14. What's genuinely real vs. simulated (even at full local)

- **Real:** TLS chains, OIDC SSO, secrets via Vault k8s-auth, policy admission,
  network policy, image signing/verification, backup/restore, the full GitOps +
  promotion process, and the metrics/logs/traces correlation already wired.
- **Simulated:** hardware **fault domains** (multi-node kind = containers on one
  host); **workload identity** (Vault k8s-auth models IRSA, isn't cloud IAM);
  single-host blast radius. Patterns faithful; physical resilience is not.

---

## 15. First concrete step

Phase 0 is the unblock-everything step and the only one with a sharp edge (CA
trust on the kind nodes):
1. Recreate clusters with `disableDefaultCNI: true` + Cilium.
2. Generate the root CA, mount it into the nodes, trust it on the host.
3. Install cert-manager + trust-manager; confirm a test `Certificate` issues and
   `https://<anything>.dev.local` is green.

A fast early win that needs none of the above: **put the new Loki/Tempo on PVCs
(§8/§10)** so observability data survives a restart — small change, immediate
realism, and it sets up the Kyverno "no emptyDir for stateful" rule later.

Once Phase 0 is solid, the remaining phases are additive `Application`s that
Argo reconciles — the same workflow the lab already demonstrates.
