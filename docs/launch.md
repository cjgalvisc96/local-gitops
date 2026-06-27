# Launch

The simplest "how do I run it" guide. For the *why* and the details, see the other pages — this one
is just the steps.

## What you get

**One command** builds a complete GitOps platform on your machine — no cloud account, no internet
services, everything in Docker:

- **3 Kubernetes clusters** (`kind`): `management`, `dev`, `prod`.
- **Gitea** — a local GitHub, where your config and apps live.
- **Argo CD** on `dev` and `prod` — watches Gitea and deploys what changes.
- **Observability** — Grafana, Prometheus, Loki, Tempo.
- **floci** — a fake local AWS (registry + secrets).

## Before you start

- **Linux** with **Docker** running.
- **git** and **curl**.

Install the pinned command-line tools (one time):

```bash
task tools
```

## Build the lab (one command)

```bash
task install
```

It takes a few minutes and prints the URLs when it's done. That's the whole platform up.

## Open it

You don't need to edit `/etc/hosts` — the installer wires DNS for you. One password for
**everything**: `adminlocal1`.

| Open this | What it is | Login |
|---|---|---|
| <http://gitea.dev.local> | Gitea (git server) | `adminlocal` / `adminlocal1` |
| <http://argo.dev.local> | Argo CD — dev | `admin` / `adminlocal1` |
| <http://argo.prod.local> | Argo CD — prod | `admin` / `adminlocal1` |
| <http://grafana.dev.local> | Grafana — dev | `admin` / `adminlocal1` |
| <http://grafana.prod.local> | Grafana — prod | `admin` / `adminlocal1` |

(Gitea's user is `adminlocal`, not `admin`, because Gitea reserves the name `admin`.)

## Put an app on it

The platform comes up **empty of apps on purpose** — each app adds itself. For the todo-app, after
the lab is up, run these from the **app repo** (one time each):

```bash
task gitea:create-repo      # create the app's repo in Gitea
task argo:add-gitea-repo    # tell Argo CD about it (dev + prod)
task gitea:ship             # push the code → the pipeline builds it → Argo deploys it
```

Then every time you change the app, just `task gitea:ship` again.

## Change the platform itself

If you edit **this** repo (`platform-config/` or `gitops-apps/`), push it to the lab so Argo picks it
up — no reinstall needed:

```bash
task gitea:ship
```

## Tear it down

```bash
task prune          # remove everything this lab created
task prune:all      # the above, plus uninstall the mise-managed CLI tools
```

## Start over (from scratch)

```bash
task prune          # 1. tear down
task install        # 2. rebuild the platform
                    # 3. onboard the app again from the app repo:
                    #    gitea:create-repo → argo:add-gitea-repo → gitea:ship
```
