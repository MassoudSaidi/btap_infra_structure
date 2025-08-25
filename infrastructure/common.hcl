# This file is the single source of truth for global constants.
# It should contain no provider or backend configurations, only local variables.

locals {
  # --- Global Settings ---
  aws_region        = "ca-central-1"
  company           = "btap"
  cognito_app_name  = "btap-identity"



  # Set this variable to switch backends
  use_local_backend = true  # Set to false for S3  

  # --- Naming Conventions for Backend Resources ---
  # We define these here so the bootstrap code and the live code can both see them.
  terraform_state_bucket_name  = "${local.company}-tf-state-bucket-unique" # S3 names must be globally unique
  terraform_locks_table_name = "${local.company}-tf-locks-table"
}