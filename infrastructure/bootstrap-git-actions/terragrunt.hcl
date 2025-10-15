# This file connects our common variables to the bootstrap Terraform code.

# Read the common variables from the root common.hcl file.
locals {
  # The read_terragrunt_config function parses another HCL file and returns its content.
  # We expose its locals block so we can use it below.
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  project_root = get_repo_root()
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region                   = "ca-central-1"
  profile                  = "dev"
  shared_config_files      = ["${local.project_root}/.aws/config"]
  shared_credentials_files = ["${local.project_root}/.aws/credentials"]
}
EOF
}


# Pass the values from the common config into the bootstrap module's input variables.
inputs = {
  aws_region          = local.common_vars.locals.aws_region
}