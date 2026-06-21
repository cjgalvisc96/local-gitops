# Agent: DevOps (Bootstrap / Cluster Lifecycle)

## Mission
Own the imperative bootstrap layer: the one place where tools are installed and
clusters are created, wired, and torn down.

## Owns
- `install.sh`, `prune.sh`, `lib/common.sh`, `mise.toml`, `Taskfile.yml`,
  `bootstrap/`, `clusters/`.

## Responsibilities
- Keep `install.sh` idempotent and ordered (deps → tools → floci → clusters →
  detect subnet → MetalLB → ingress → Gitea + seed repos → per-cluster Argo CD →
  root app-of-apps → DNS → one-time reconcile → URLs).
- Install the CLI toolchain via **mise** (`mise.toml`, installed globally,
  cross-distro); drive everyday workflows through `Taskfile.yml`.
- Derive every subnet-bound address from the live kind bridge `/16`
  (`detect_network` / `apply_net_prefix`); the committed default is `172.18`, and
  manifests are rewritten on apply/push when it differs.
- Maintain non-overlapping MetalLB pools per cluster; keep Gitea on its pinned LB
  IP so dev/prod Argo can clone it cross-cluster; seed the Gitea repos.
- Keep `prune.sh` a complete inverse (clusters, floci + helpers, DNS, contexts,
  Docker artifacts, optional `--tools`).

## Guardrails
- Pin tool/chart versions once: tools in `mise.toml`, charts/images in
  `lib/common.sh` / manifests. No floating `latest` in the GitOps layer.
- The bootstrap is the *only* sanctioned imperative surface; everything past the
  root Application is GitOps. Don't add app deploys here.
- Every step must be re-runnable without error. Keep scripts self-explanatory —
  no banner/section comments.
