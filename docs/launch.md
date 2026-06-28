# Launch

The simplest "how do I run it" guide. For the *why* and the details, see the other pages — this one
is just the steps.

## What you get

**One command** builds a complete GitOps platform on your machine — no cloud account, no internet
services, everything in Docker:

- **3 Kubernetes clusters**: a `management` cluster (`kind`) plus two **floci-EKS**
  workload clusters, `dev` and `prod` (k3s containers emulating EKS on floci).
- **Gitea** — a local GitHub, where your config and apps live (management cluster).
- **Argo CD** on `dev` and `prod` — watches Gitea and deploys what changes.
- **Observability** — Grafana, Prometheus, Loki, Tempo, on `dev` and `prod`.
- **floci** — a fake local AWS (registry + secrets + messaging).

Argo CD and Grafana are **live before any app** — the platform owns and stands up
the workload clusters, so `argo.*.local` and `grafana.*.local` answer the moment
`task install` finishes.

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

You don't need to edit `/etc/hosts` — the installer wires DNS for you. Gitea and
Grafana share the password `adminlocal1`. Everything is **http** (Argo CD runs
insecure), never https.

| Open this | What it is | Login |
|---|---|---|
| <http://gitea.dev.local> | Gitea (git server) | `adminlocal` / `adminlocal1` |
| <http://argo.dev.local> | Argo CD — dev | `admin` / `task argo:password ENV=dev` |
| <http://argo.prod.local> | Argo CD — prod | `admin` / `task argo:password ENV=prod` |
| <http://grafana.dev.local> | Grafana — dev | `admin` / `adminlocal1` |
| <http://grafana.prod.local> | Grafana — prod | `admin` / `adminlocal1` |

(Gitea's user is `adminlocal`, not `admin`, because Gitea reserves the name `admin`.
Argo CD's admin password is per-cluster random — print it with `task argo:password`.)

## Put an app on it

The platform comes up **empty of apps on purpose** — each app adds itself. For the todo-app, after
the lab is up, run these from the **app repo** (one time each):

```bash
task gitea:create-repo      # create the app's repo in Gitea
task gitea:ship             # push the code → the DEV pipeline builds it → Argo deploys it
```

`gitea:ship` triggers the app's DEV (automatic) Gitea Actions pipeline, which
builds the image, provisions the app's own cloud resources on floci, and registers
the app's Argo Application with the platform's dev cluster. PROD is a deliberate
manual promote — the prod cluster already exists from `task install`, so only the
deploy is manual. Then every time you change the app, just `task gitea:ship` again.

## Change the platform itself

If you edit **this** repo (the `gitops-apps/` overlays — e.g. observability), push it
to the lab so Argo picks it up — no reinstall needed:

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
                    #    gitea:create-repo → gitea:ship
```
