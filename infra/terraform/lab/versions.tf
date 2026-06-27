# Lab INFRA, declaratively. Terraform/Terragrunt owns the non-Kubernetes-object
# resources the lab is built on: the floci (LocalStack) container, the kind
# management cluster, and the Gitea Actions runner container. The Kubernetes
# objects themselves (MetalLB, ingress-nginx, Gitea, manifests, observability)
# are applied declaratively with helm/kubectl by `task install` AFTER this stack
# brings the cluster up — so there is no kind-cluster→k8s-provider bootstrap race.
terraform {
  required_version = ">= 1.5"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
