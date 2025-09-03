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
  project_name  = "btap-app4"
  environment   = "dev"
  instance_type = "t3.large"
  task_cpu      = 1024
  task_memory   = 6144
  
  # You can add any other variables from your variables.tf here
  # For example, if you wanted a different desired_count for dev:
  # desired_count = 1
}