# .agents — Harness engineering (multi-agent setup)

Role definitions for a small platform-engineering "team" that operates this
GitOps lab. Each role is a focused agent persona with a mission, the parts of
the repo it owns, and its guardrails. They compose: the **lead** decomposes and
delegates; **architect** designs, **developer** implements, **tester** verifies,
**devops** runs the bootstrap, **sre** owns reliability & observability.

| Role | Owns | One-line mission |
|------|------|------------------|
| [lead](lead/agent.md) | the whole repo | Decompose work, delegate, integrate, keep GitOps invariants |
| [architect](architect/agent.md) | `platform-config/`, repo layout | Design the app-of-apps, AppProjects, env promotion |
| [developer](developer/agent.md) | `gitops-apps/` | Implement stack & manifest changes via Git |
| [tester](tester/agent.md) | renders & smoke tests | Prove every change builds and syncs cleanly |
| [devops](devops/agent.md) | `install.sh`, `prune.sh`, `bootstrap/` | Own the bootstrap & cluster lifecycle |
| [sre](sre/agent.md) | `observability/`, SLOs | Keep it observable, healthy, recoverable |

## How the lab is wired (shared mental model)
- **Three kind clusters.** `management` runs Gitea (the in-cluster Git server);
  `dev` and `prod` each run **their own Argo CD** — there is no central Argo on
  management.
- **App-of-apps, per env.** Each workload cluster's `root` Application points at
  `platform-config/envs/<env>` (recursed). That dir holds the env's `AppProject`
  plus one Argo `Application` per stack (`platform`, `observability`,
  `dependencies`, `external-secrets`, `todo-app`), each pointing at
  `gitops-apps/<stack>/overlays/<env>`. No ApplicationSets / cluster generators.
- **Cross-cluster Git.** dev/prod Argo clone Gitea over a pinned MetalLB LB IP
  (`<prefix>.255.209`). The `<prefix>` is the live kind bridge `/16`, derived at
  install time (default `172.18`, but adapts if that subnet is taken).
- **The app is external & off by default.** `todo-app` lives in its own repo
  (`modular-monolithic-app`), mirrored to Gitea and deployed only with
  `DEPLOY_APP=true`. With it off, the `todo-app` + `dependencies` Applications are
  omitted from the push.
- **Tooling.** The CLI toolchain is pinned in `mise.toml` and installed globally
  by `install.sh`; common workflows run through `Taskfile.yml` (`task install`,
  `task validate`, `task k8s:status`, `task k8s:trivy`, …).

**Shared invariant for every role:** the clusters are downstream of Git.
Nothing is changed with imperative `kubectl apply`/`helm` on dev/prod — you change
a manifest in `gitops-apps/` (or `platform-config/`), commit, and let Argo CD
reconcile. The only imperative surface is the bootstrap layer in `install.sh`.

**Code style:** prefer self-explanatory manifests and scripts over comments —
clear names and structure, not narration. Don't add banner/section comments.
