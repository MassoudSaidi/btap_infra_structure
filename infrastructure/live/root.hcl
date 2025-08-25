# This root file now uses a 'generate' block for flexible backend configuration.

# Read the global variables from the common.hcl file at the project root.
locals {
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

# This 'generate' block will create a file named 'backend.tf' inside the
# .terragrunt-cache directory right before running 'terraform init'.
generate "backend" {
  path      = "backend.tf"  # The name of the file to create
  if_exists = "overwrite_terragrunt" # Always overwrite the file with the latest config

  # The content of the file is determined by our conditional logic.
  contents = <<EOF
terraform {
  backend "${local.common_vars.locals.use_local_backend ? "local" : "s3"}" {
    ${local.common_vars.locals.use_local_backend ? "path = \"${get_terragrunt_dir()}/terraform.tfstate\"" : ""}
    ${!local.common_vars.locals.use_local_backend ? "bucket         = \"${local.common_vars.locals.terraform_state_bucket_name}\"" : ""}
    ${!local.common_vars.locals.use_local_backend ? "key            = \"${path_relative_to_include()}/terraform.tfstate\"" : ""}
    ${!local.common_vars.locals.use_local_backend ? "region         = \"${local.common_vars.locals.aws_region}\"" : ""}
    ${!local.common_vars.locals.use_local_backend ? "encrypt        = true" : ""}
    ${!local.common_vars.locals.use_local_backend ? "dynamodb_table = \"${local.common_vars.locals.terraform_locks_table_name}\"" : ""}
  }
}
EOF
}

# Expose the global region as an input for all child environments.
inputs = {
  aws_region = local.common_vars.locals.aws_region
}