############################################
# floci — the local AWS (LocalStack) emulator
############################################
resource "docker_image" "floci" {
  name         = var.floci_image
  keep_locally = true
}

resource "docker_container" "floci" {
  name    = var.floci_container
  image   = docker_image.floci.image_id
  user    = "root"
  restart = "unless-stopped"

  ports {
    internal = var.floci_port
    external = var.floci_port
  }

  # floci spins up child containers (e.g. the EKS k3s nodes) on the host daemon.
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  labels {
    label = "com.docker.compose.project"
    value = var.project_name
  }
  labels {
    label = "com.docker.compose.service"
    value = "floci"
  }
}

############################################
# floci-EKS workload clusters (k3s)
#
# The platform stands up the app's dev/prod workload clusters as k3s containers
# — the same shape floci's EKS plugin produces (name floci-eks-<app>-<env>,
# kubeconfig at /etc/rancher/k3s/k3s.yaml, API on 6443). traefik + servicelb are
# disabled so the platform's MetalLB + ingress-nginx own LB/ingress. The app's
# tasks reference these by name; `task eks:bootstrap` then wires Argo +
# observability so argo.<env>.local / grafana.<env>.local work before any deploy.
############################################
resource "docker_image" "k3s" {
  name         = var.k3s_image
  keep_locally = true
}

resource "docker_container" "eks" {
  for_each = { for i, e in var.eks_envs : e => i }

  name       = "floci-eks-${var.app_project}-${each.key}"
  image      = docker_image.k3s.image_id
  privileged = true
  restart    = "unless-stopped"
  command    = ["server", "--disable=traefik", "--disable=servicelb", "--tls-san=127.0.0.1", "--write-kubeconfig-mode=644"]

  # Join the kind network (created with the management cluster) so MetalLB can
  # L2-advertise the EKS LB IPs (.230/.240) where the host + Gitea LB can reach
  # them, and the in-EKS Argo can pull from Gitea at 172.18.255.209. kind's
  # bridge has outbound NAT, so image pulls still work.
  networks_advanced {
    name = "kind"
  }
  depends_on = [kind_cluster.management]

  # Fixed host API port per env (dev=6443, prod=6444) — deterministic for
  # Terraform; `task eks:kubeconfig` reads whatever HostPort docker reports.
  ports {
    internal = 6443
    external = 6443 + each.value
  }

  # k3s-in-docker needs writable /run + /var/run.
  tmpfs = {
    "/run"     = ""
    "/var/run" = ""
  }

  labels {
    label = "com.docker.compose.project"
    value = var.project_name
  }
  labels {
    label = "com.docker.compose.service"
    value = "floci-eks-${each.key}"
  }
}

############################################
# kind — the management cluster (Gitea host)
############################################
resource "kind_cluster" "management" {
  name           = var.mgmt_cluster
  node_image     = var.node_image
  wait_for_ready = true
}

############################################
# Gitea Actions runner
#
# Created on the SECOND apply (once Gitea is up and `task install` has fetched a
# registration token). The rendered runner-config bind-mounts this repo into every
# job at /opt/local-gitops, so the app pipeline can call platform-owned tasks.
############################################
resource "local_file" "runner_config" {
  count    = var.runner_token != "" ? 1 : 0
  filename = "${var.repo_root}/bootstrap/gitea/runner-config.rendered.yaml"
  content  = replace(file("${var.repo_root}/bootstrap/gitea/runner-config.yaml"), "__LOCAL_GITOPS_DIR__", var.repo_root)
}

resource "docker_image" "runner" {
  count        = var.runner_token != "" ? 1 : 0
  name         = var.runner_image
  keep_locally = true
}

resource "docker_container" "runner" {
  count        = var.runner_token != "" ? 1 : 0
  name         = var.runner_container
  image        = docker_image.runner[0].image_id
  network_mode = "host"
  restart      = "unless-stopped"

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }
  volumes {
    host_path      = local_file.runner_config[0].filename
    container_path = "/config.yaml"
    read_only      = true
  }

  env = [
    "CONFIG_FILE=/config.yaml",
    "GITEA_INSTANCE_URL=${var.gitea_url}",
    "GITEA_RUNNER_REGISTRATION_TOKEN=${var.runner_token}",
    "GITEA_RUNNER_NAME=${var.runner_name}",
  ]

  labels {
    label = "com.docker.compose.project"
    value = var.project_name
  }
  labels {
    label = "com.docker.compose.service"
    value = "gitea-runner"
  }

  depends_on = [kind_cluster.management]
}
