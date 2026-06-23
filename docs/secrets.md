# Secrets

## No secret values in Git

The rule is absolute: **no secret values are ever committed**. Manifests reference
secrets; they never contain them.

```
ExternalSecret ──▶ ClusterSecretStore (aws-ssm) ──▶ floci (local AWS emulator)
```

- The **External Secrets Operator** runs in each workload cluster (its own
  Application, `external-secrets.yaml`).
- A `ClusterSecretStore` named `aws-ssm` points at floci's SSM API.
- An `ExternalSecret` declares which SSM parameters to pull and what Kubernetes
  `Secret` to materialise.

## floci — local AWS

[floci](https://github.com/floci-io/floci) emulates AWS locally. `install.sh`
starts it as a Docker container, seeds SSM parameters and ECR repositories, and
the External Secrets Operator pulls from it.

- Pods reach floci's host-published port through the kind bridge gateway
  (`<prefix>.0.1:4566`); the host seeds via `localhost:4566`.
- floci credentials are dummy (`test` / `test`) — they are not real and not
  sensitive.
- `prune.sh` stops and removes the container.

## Eventual consistency

The `ClusterSecretStore` / `ExternalSecret` depend on the operator's CRDs, which a
separate Application installs. Argo self-heal reconciles them once the operator is
up — so a first-sync ordering blip resolves itself.
