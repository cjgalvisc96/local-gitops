---
description: Show the health of the GitOps lab — clusters, Argo apps, and ingress IPs.
---

Report the current state of the lab. Run (and summarize, don't dump):

```bash
kind get clusters
for c in management dev prod; do
  echo "== $c =="
  kubectl --context "kind-$c" get nodes -o wide 2>/dev/null
  kubectl --context "kind-$c" -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath="ingress $c {.status.loadBalancer.ingress[0].ip}{'\n'}" 2>/dev/null
done
# Argo CD runs in each workload cluster, not on management:
for c in dev prod; do
  echo "== $c argo =="
  kubectl --context "kind-$c" -n argocd get applications.argoproj.io 2>/dev/null
done
```

(`task k8s:status` is the shortcut for the Argo part.)

Then give a one-paragraph verdict: which clusters are up, which Argo apps are
Synced/Healthy vs degraded per env, and the ingress IPs. Flag anything not
Healthy and suggest the next step (usually `task k8s:sync` or checking the
failing app).
