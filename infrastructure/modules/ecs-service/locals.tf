# This block uses the input variables to create a consistent set of names for all resources.
locals {
  # The base name combines the project and environment for uniqueness, e.g., "ecs-app-dev"
  base_name = "${var.project_name}-${var.environment}"

  # A map of all the names we will use in our resources.
  # We can now reference these as `local.cluster_name`, `local.vpc_name`, etc.
  names = {
    vpc_name                 = "${local.base_name}-vpc"
    cluster_name             = "${local.base_name}-cluster"
    service_name             = "${local.base_name}-service"
    task_family              = "${local.base_name}-task"
    
    alb_name                 = "${local.base_name}-alb"
    target_group_name        = "${local.base_name}-tg"
    
    alb_sg_name              = "${local.base_name}-alb-sg"
    ecs_sg_name              = "${local.base_name}-ecs-sg"
    
    asg_name_prefix          = "${local.base_name}-asg-" # Prefixes must end with a hyphen
    launch_template_prefix   = "${local.base_name}-lt-"
    
    iam_role_name            = "${local.base_name}-instance-role"
    iam_profile_name         = "${local.base_name}-instance-profile"
    
    capacity_provider_name   = "${local.base_name}-capacity-provider"
  }
}