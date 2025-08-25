# This file connects our common variables to the bootstrap Terraform code.

# Read the common variables from the root common.hcl file.
locals {
  # The read_terragrunt_config function parses another HCL file and returns its content.
  # We expose its locals block so we can use it below.
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

# Pass the values from the common config into the bootstrap module's input variables.
inputs = {
  aws_region          = local.common_vars.locals.aws_region
}