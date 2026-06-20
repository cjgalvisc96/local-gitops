# .agents — Harness engineering (multi-agent setup)

Role definitions for a small platform-engineering "team" that operates this
GitOps lab. Each role is a focused agent persona with a mission, the parts of
the repo it owns, and its guardrails. They compose: the **lead** decomposes and
delegates; **architect** designs, **developer** implements, **tester** verifies,
**devops** runs the bootstrap, **sre** owns reliability & observability.

| Role | Owns | One-line mission |
|------|------|------------------|
| [lead](lead/agent.md) | the whole repo | Decompose work, delegate, integrate, keep GitOps invariants |
| [architect](architect/agent.md) | `platform-config/`, repo layout | Design clusters, ApplicationSets, env promotion |
| [developer](developer/agent.md) | `gitops-apps/` | Implement app & manifest changes via Git |
| [tester](tester/agent.md) | renders & smoke tests | Prove every change builds and syncs cleanly |
| [devops](devops/agent.md) | `install.sh`, `prune.sh`, `bootstrap/` | Own the bootstrap & cluster lifecycle |
| [sre](sre/agent.md) | `observability/`, SLOs | Keep it observable, healthy, recoverable |

**Shared invariant for every role:** the clusters are downstream of Git.
Nothing is changed with imperative `kubectl apply`/`helm` on dev/prod — you change
a manifest in `gitops-apps/` (or `platform-config/`), commit, and let Argo CD
reconcile. The only imperative surface is the bootstrap layer in `install.sh`.
