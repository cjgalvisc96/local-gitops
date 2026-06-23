# Networking & DNS

## Dynamic subnet derivation

The lab does **not** hard-code an IP range. At install time it detects the live
kind docker bridge `/16` and derives every address from it (`detect_network` /
`apply_net_prefix` in `lib/common.sh`). The default prefix is `172.18`, but if
that subnet is already taken (for example by another docker network) kind lands
on `172.19` and the lab follows.

From the live prefix it computes:

- the MetalLB address pools for each cluster,
- the pinned Gitea LoadBalancer IP (`<prefix>.255.209`),
- the floci gateway (`<prefix>.0.1`).

`subst_net` / `subst_net_tree` rewrite the committed default prefix to the live
one when manifests are applied or pushed, so the repo stays clean while the
running lab uses real addresses.

## MetalLB + ingress-nginx

MetalLB hands out LoadBalancer IPs on the kind docker network, which is routable
from a Linux host. ingress-nginx then routes by host. One app per namespace;
ingress hosts follow `gitea|argo|grafana|<app>.<env>.local`.

## Cross-cluster Git

`dev` and `prod` Argo CD clone Gitea over its **pinned** MetalLB LoadBalancer IP
(`<prefix>.255.209`), so the URL is stable across reinstalls and reachable from
both workload clusters.

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
