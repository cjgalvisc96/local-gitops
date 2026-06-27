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
