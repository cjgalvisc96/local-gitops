variable "project_name" {
  description = "Lab project label applied to the docker resources."
  type        = string
  default     = "local-gitops"
}

variable "repo_root" {
  description = "Absolute path to the local-gitops checkout (host path the runner job-mount and runner-config reference)."
  type        = string
}

variable "floci_image" {
  description = "floci (LocalStack) image."
  type        = string
  default     = "floci/floci:latest"
}

variable "floci_container" {
  description = "floci container name."
  type        = string
  default     = "floci"
}

variable "floci_port" {
  description = "floci edge port (host = container)."
  type        = number
  default     = 4566
}

variable "app_project" {
  description = "App project embedded in the floci-EKS container names (floci-eks-<app_project>-<env>), matching the app's task references."
  type        = string
  default     = "todo-app"
}

variable "k3s_image" {
  description = "k3s image for the floci-EKS workload clusters (same shape floci's EKS plugin produces)."
  type        = string
  default     = "rancher/k3s:v1.31.5-k3s1"
}

variable "eks_envs" {
  description = "Environments to stand up a floci-EKS (k3s) workload cluster for. Host API port = base + index (dev=6443, prod=6444)."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "node_image" {
  description = "kind node image."
  type        = string
  default     = "kindest/node:v1.31.4"
}

variable "mgmt_cluster" {
  description = "kind management cluster name (KIND runs only this one — Gitea host)."
  type        = string
  default     = "management"
}

variable "runner_image" {
  description = "Gitea act_runner image."
  type        = string
  default     = "gitea/act_runner:0.2.11"
}

variable "runner_container" {
  description = "Runner container name."
  type        = string
  default     = "gitea-runner"
}

variable "runner_name" {
  description = "Runner display name registered with Gitea."
  type        = string
  default     = "lab-runner"
}

variable "gitea_url" {
  description = "In-cluster Gitea URL the runner registers against (the MetalLB Git LB)."
  type        = string
  default     = "http://172.18.255.209:3000"
}

variable "runner_token" {
  description = "Gitea runner registration token. Empty on the first apply (cluster only); `task install` fills it after Gitea is up, on a second apply, to create the runner."
  type        = string
  default     = ""
  sensitive   = true
}
