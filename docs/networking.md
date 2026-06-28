# Networking & DNS

## Dynamic subnet derivation

The lab does **not** hard-code an IP range. At install time it detects the live
kind docker bridge `/16` and derives every address from it (`detect_network` /
`apply_net_prefix` in `lib/common.sh`). The default prefix is `172.18`, but if
that subnet is already taken (for example by another docker network) kind lands
on `172.19` and the lab follows.

From the live prefix it computes:

- the management cluster's MetalLB pool (`<prefix>.255.200-.209`),
- the per-EKS single-IP pools (dev `<prefix>.255.230`, prod `<prefix>.255.240`),
- the pinned Gitea LoadBalancer IP (`<prefix>.255.209`),
- the floci gateway (`<prefix>.0.1`).

`subst_net` / `subst_net_tree` rewrite the committed default prefix to the live
one when manifests are applied or pushed, so the repo stays clean while the
running lab uses real addresses.

## Who owns which IP

The platform owns the clusters and their ingress. The **management** kind cluster
hosts **only Gitea**; everything else lives on the **floci-EKS** workload clusters.
The floci-EKS k3s containers are attached to the kind docker network so their
MetalLB-advertised IPs are reachable from the host and from Gitea.

| Host | IP | Cluster | Owner |
|------|-----|---------|-------|
| `gitea.dev.local` | `<prefix>.255.200` (mgmt ingress) | management (kind) | platform |
| `argo.dev.local` | `<prefix>.255.230` | floci-EKS dev | platform |
| `argo.prod.local` | `<prefix>.255.240` | floci-EKS prod | platform |
| `grafana.dev.local` | `<prefix>.255.230` | floci-EKS dev | platform |
| `grafana.prod.local` | `<prefix>.255.240` | floci-EKS prod | platform |
| `todo-app.dev.local` | `<prefix>.255.230` | floci-EKS dev | the app |
| `todo-app.prod.local` | `<prefix>.255.240` | floci-EKS prod | the app |

The default prefix is `172.18`, so out of the box that is `.200` / `.230` / `.240`.

## MetalLB + ingress-nginx

MetalLB hands out LoadBalancer IPs on the kind docker network, which is routable
from a Linux host. ingress-nginx then routes by host. Each cluster runs its own
MetalLB + ingress-nginx: the management cluster uses the `.200-.209` pool, and each
floci-EKS cluster a dedicated single-IP pool (dev `.230`, prod `.240`) that sits
**outside** the management pool to avoid L2 collisions. Ingress hosts follow
`gitea|argo|grafana|<app>.<env>.local`.

## Cross-cluster Git

The in-EKS `dev` and `prod` Argo CD clone Gitea over its **pinned** MetalLB
LoadBalancer IP (`<prefix>.255.209`), so the URL is stable across reinstalls and
reachable from both workload clusters.

## DNS

DNS is wired automatically — no manual `/etc/hosts` edits:

- A dedicated `dnsmasq` on `127.0.0.1:5300` resolves `*.dev.local` /
  `*.prod.local` to the right cluster's ingress IP.
- A `systemd-resolved` drop-in points those domains at that dnsmasq.
- On hosts without systemd-resolved, the installer falls back to an automated
  `/etc/hosts` block marked with `# gitops-lab` (which `prune.sh` removes).

Check it end to end:

```bash
task dns:test       # curl every lab host and print the HTTP status
```
