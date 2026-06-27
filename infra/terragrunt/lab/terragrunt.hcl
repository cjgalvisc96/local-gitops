# The lab infra unit — floci + kind management cluster + Gitea runner.
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/infra/terraform//lab"
}
