# This is a Terragrunt helper function. It finds the root of the Git repo,
# which is a reliable way to find the root of the project.
locals {
  project_root = get_repo_root()
}

# This block tells Terragrunt to generate a provider.tf file inside the .terragrunt-cache.
# This is the modern, recommended way to configure providers with Terragrunt.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region                   = "ca-central-1"
  profile                  = "dev"

  # Explicitly tell the provider where to find the config files using an absolute path.
  # This makes the configuration completely independent of the shell environment.
  shared_config_files      = ["${local.project_root}/.aws/config"]
  shared_credentials_files = ["${local.project_root}/.aws/credentials"]
}
EOF
}



# This tells Terragrunt where to find the module code.
# The path is relative to this terragrunt.hcl file.
terraform {
  source = "../../modules/ecs-service"
}

# This tells Terragrunt to include all the variables from the parent
# directory's terragrunt.hcl file. We will create this next.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# These are the input variables for this specific environment.
# Terragrunt will pass these to your module's variables.tf file.
inputs = {
  project_name  = "btap-app-test2"
  environment   = "dev-test2"
  instance_type = "t3.large"
  task_cpu      = 1024
  task_memory   = 6144
  
  # You can add any other variables from your variables.tf here
  # For example, if you wanted a different desired_count for dev:
  # desired_count = 1
}