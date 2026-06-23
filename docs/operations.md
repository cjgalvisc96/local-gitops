# Operations

All workflows run through `Taskfile.yml`. Run `task` (or `task default`) to list
everything.

## Lifecycle

| Task | Does |
|------|------|
| `task tools` | install the pinned CLI toolchain via mise |
| `task install` | build the full lab |
| `task install:app` | build the lab and deploy the todo-app (`DEPLOY_APP=true`) |
| `task prune` | tear down clusters, floci, DNS and Docker artifacts |
| `task prune:all` | the above and uninstall the mise-managed tools |

With `DEPLOY_APP=true`, `install.sh` also starts the **Gitea Actions runner** and
applies the app's floci **Terraform** stack at bootstrap; `prune` removes the
runner. The app's own pipelines drive build/deploy/promote — see
[CI/CD](cicd.md).

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
