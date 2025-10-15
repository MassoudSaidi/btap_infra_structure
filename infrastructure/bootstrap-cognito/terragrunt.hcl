# Find the root of the Git repository to reliably locate the .aws folder.
# This file connects our common variables to the bootstrap Terraform code.

# Read the common variables from the root common.hcl file.
locals {
  # The read_terragrunt_config function parses another HCL file and returns its content.
  # We expose its locals block so we can use it below.
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  project_root = get_repo_root()

}

# This block generates the provider configuration for Terraform. It is the
# key to making your deployment self-contained and reliable.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region                   = "ca-central-1"
  profile                  = "dev"

  # Explicitly tell the provider where to find the local config files.
  shared_config_files      = ["${local.project_root}/.aws/config"]
  shared_credentials_files = ["${local.project_root}/.aws/credentials"]
}
EOF
}




# Pass the values from the common config into the bootstrap module's input variables.
inputs = {
  aws_region          = local.common_vars.locals.aws_region
  app_name            = local.common_vars.locals.cognito_app_name
}