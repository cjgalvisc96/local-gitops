# Operations

All workflows run through `Taskfile.yml`. Run `task` (or `task default`) to list
everything.

## Lifecycle

| Task | Does |
|------|------|
| `task tools` | install the pinned CLI toolchain via mise |
| `task install` | build the full lab (app-agnostic — no specific app) |
| `task install:app` | build the lab and keep an app's Argo Applications in `platform-config` (`DEPLOY_APP=true`) |
| `task gitea:ship` | re-push `platform-config` + `gitops-apps` so Argo reconciles platform edits (no reinstall) |
| `task prune` | tear down clusters, floci, DNS and Docker artifacts |
| `task prune:all` | the above and uninstall the mise-managed tools |

`install.sh` always starts the **Gitea Actions runner** (the lab's CI/CD); `prune`
removes it. The platform installs app-agnostic — **apps onboard themselves** into
the running lab (the todo-app uses its `gitea:create-repo` / `argo:add-gitea-repo`
/ `gitea:ship` tasks; see [Launch](launch.md)). `DEPLOY_APP=true` only seeds an
app's floci state and keeps its Applications at bootstrap. The app's own pipelines
drive build/deploy/promote — see [CI/CD](cicd.md).

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
| `task k8s:status` | clusters + Argo application health (dev, prod) |
| `task k8s:pods` | pods across all clusters (`ENV=dev` to scope) |
| `task k8s:apps` | Argo applications for `ENV` (default dev) |
| `task k8s:sync ENV=dev` | hard-refresh + sync every Argo app in `ENV` |
| `task k8s:trivy ENV=dev` | Trivy scan a cluster, or `IMG=<image>` for one image |
| `task argo:password` | print the Argo CD admin password per workload cluster |
| `task argo:repos` | show the Gitea repos Argo CD is linked to (`ENV=dev`) |

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
