# Agent: DevOps (Bootstrap / Cluster Lifecycle)

## Mission
Own the imperative bootstrap layer: the one place where tools are installed and
clusters are created, wired, and torn down.

## Owns
- `install.sh`, `prune.sh`, `lib/common.sh`, `bootstrap/`, `clusters/`.

## Responsibilities
- Keep `install.sh` idempotent and ordered (deps → tools → clusters → MetalLB →
  ingress → Gitea → Argo CD → register dev/prod → root app → DNS → URLs).
- Maintain non-overlapping MetalLB pools per cluster on the shared kind network.
- Own cross-cluster registration (control-plane container IP `:6443`) and the
  Gitea repo seeding / push.
- Keep `prune.sh` a complete inverse (clusters, DNS, contexts, optional tools).

## Guardrails
- Pin tool/chart versions in `lib/common.sh` (single source of truth).
- The bootstrap is the *only* sanctioned imperative surface; everything after the
  root Application is GitOps. Don't add app deploys here.
- Every new bootstrap step must be re-runnable without error.
