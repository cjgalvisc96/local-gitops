---
description: Show the health of the GitOps lab — clusters, Argo apps, and ingress IPs.
---

Report the current state of the lab. Run (and summarize, don't dump):

```bash
kind get clusters
for c in management dev prod; do
  echo "== $c =="
  kubectl --context "kind-$c" get nodes -o wide 2>/dev/null
done
kubectl --context kind-management -n argocd get applications.argoproj.io 2>/dev/null
for c in management dev prod; do
  kubectl --context "kind-$c" -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath="{.metadata.name} $c {.status.loadBalancer.ingress[0].ip}{'\n'}" 2>/dev/null
done
```

Then give a one-paragraph verdict: which clusters are up, which Argo apps are
Synced/Healthy vs degraded, and the ingress IPs. Flag anything not Healthy and
suggest the next step (usually an Argo re-sync or checking the failing app).
