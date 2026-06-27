# Root Terragrunt config for the local-gitops lab INFRA (floci + kind + runner).
# Local backend — this is a throwaway local lab; state lives under the repo.
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    path = "${get_repo_root()}/infra/terraform/.lab-state/${path_relative_to_include()}/terraform.tfstate"
  }
}

# Common inputs every unit gets.
inputs = {
  repo_root = get_repo_root()
}
