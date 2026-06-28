# Secrets

## No secret values in Git

The rule is absolute: **no secret values are ever committed**. Manifests reference
secrets; they never contain them.

```
ExternalSecret ──▶ ClusterSecretStore (aws-ssm) ──▶ floci (local AWS emulator)
```

- The **External Secrets Operator** can run in a workload cluster, with a
  `ClusterSecretStore` named `aws-ssm` that points at floci's AWS API.
- An `ExternalSecret` declares which floci parameters/secrets to pull and what
  Kubernetes `Secret` to materialise.
- The app owns this wiring in **its own** repo — onboarding an app adds its
  secret manifests there, never to the platform.

## floci — local AWS

[floci](https://github.com/floci-io/floci) emulates AWS locally. The **platform's
Terraform/Terragrunt** creates the floci container as part of `task install` (see
[Architecture](architecture.md)) and `task prune` (Terragrunt destroy) removes it.

The platform does **not** seed any app's cloud resources. The app provisions its
own — **ECR, Secrets, SQS/SNS, EventBridge, S3** — through its own pipeline's
`terraform` stage (`terragrunt apply` against floci); EKS/VPC are gated off because
the platform owns the cluster (see [CI/CD](cicd.md)).

- Pods reach floci's host-published port through the docker bridge gateway
  (`<prefix>.0.1:4566`); the host seeds via `localhost:4566`.
- floci credentials are dummy (`test` / `test`) — they are not real and not
  sensitive.

## Eventual consistency

The `ClusterSecretStore` / `ExternalSecret` depend on the operator's CRDs, which a
separate Application installs. Argo self-heal reconciles them once the operator is
up — so a first-sync ordering blip resolves itself.
