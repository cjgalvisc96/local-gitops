# Operations

All workflows run through `Taskfile.yml`. Run `task` (or `task default`) to list
everything.

## Lifecycle

| Task | Does |
|------|------|
| `task tools` | install the pinned CLI toolchain via mise |
| `task install` | build the full lab — infra (Terraform/Terragrunt) + Gitea + per-EKS Argo CD + observability (app-agnostic) |
| `task eks:bootstrap ENV=<env>` | (re)bootstrap a floci-EKS cluster: MetalLB + ingress-nginx + Argo CD + observability |
| `task gitea:ship` | re-push `gitops-apps` so the in-EKS Argo reconciles platform edits (no reinstall) |
| `task prune` | Terragrunt destroy (runner + kind + floci-EKS + floci) then host cleanup |
| `task prune:all` | the above and uninstall the mise-managed tools |

`task install` provisions the infra (floci, the kind management cluster, the two
floci-EKS clusters and — on a second apply — the **Gitea Actions runner**), then
brings up Argo CD and observability on both workload clusters; `task prune`
(Terragrunt destroy) removes it all. The platform installs app-agnostic — **apps
onboard themselves** into the running lab (the todo-app uses its
`gitea:create-repo` / `gitea:ship` tasks; see [Launch](launch.md)). The app's own
pipelines drive build/deploy/promote — see [CI/CD](cicd.md).

## Validation

| Task | Does |
|------|------|
| `task validate` | render every overlay, parse YAML, lint the shell scripts |
| `task validate:kustomize` | `kustomize build` every overlay |
| `task validate:scripts` | `bash -n` + `shellcheck` the scripts |

Always validate before pushing — a change that doesn't render isn't done.

## Cluster & Argo CD

| Task | Does |
|------|------|
| `task k8s:status` | kind clusters + the floci-EKS Argo application health (`ENV=dev`) |
| `task k8s:pods` | pods on the floci-EKS cluster (`ENV=dev`) |
| `task k8s:apps` | Argo applications on the floci-EKS cluster (`ENV=dev`) |
| `task k8s:sync ENV=dev` | hard-refresh + sync every Argo app on the floci-EKS cluster |
| `task k8s:trivy ENV=dev` | Trivy scan a floci-EKS cluster, or `IMG=<image>` for one image |
| `task argo:password ENV=dev` | print the in-EKS Argo CD admin login (per-cluster, random) |
| `task argo:repos ENV=dev` | show the Gitea repos the in-EKS Argo CD is linked to |

## DNS

| Task | Does |
|------|------|
| `task dns:test` | curl every lab ingress host and print the HTTP status |

## Documentation

| Task | Does |
|------|------|
| `task docs:serve` | serve this site locally at `http://127.0.0.1:8080` (live reload) |
| `task docs:build` | build the static site into `site/` |

The docs are [MkDocs](https://www.mkdocs.org/) with the
[Material](https://squidfunk.github.io/mkdocs-material/) theme (`mkdocs.yml` +
`docs/`). They run on demand through `uv` at pinned versions (the `MKDOCS` var in
`Taskfile.yml`); `uv` itself is pinned in `mise.toml`, so `task tools` is all the
setup you need.
