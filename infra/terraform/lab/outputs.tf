output "floci_endpoint" {
  description = "floci edge endpoint."
  value       = "http://localhost:${var.floci_port}"
}

output "kube_context" {
  description = "kubectl context for the management cluster (kind prefixes with kind-)."
  value       = "kind-${var.mgmt_cluster}"
}

output "kubeconfig" {
  description = "Raw kubeconfig for the management cluster."
  value       = kind_cluster.management.kubeconfig
  sensitive   = true
}

output "runner_created" {
  description = "Whether the Gitea Actions runner has been provisioned (true after the token-bearing apply)."
  value       = nonsensitive(var.runner_token != "")
}
