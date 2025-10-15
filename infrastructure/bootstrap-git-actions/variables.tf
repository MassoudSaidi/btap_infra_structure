# # AWS Admin Credentials (to create IAM user)
# variable "aws_admin_access_key" {
#   description = "AWS Access Key ID of an admin user"
#   type        = string
#   sensitive   = true
# }

# variable "aws_admin_secret_key" {
#   description = "AWS Secret Access Key of an admin user"
#   type        = string
#   sensitive   = true
# }

variable "aws_region" {
  description = "AWS region to use"
  type        = string
  default     = "ca-central-1"
}

# Docker Credentials
variable "developer_name" {
  description = "Could be any name (it's just used for local state management)"
  type        = string
}


# Docker Credentials
variable "docker_username" {
  description = "Docker registry username"
  type        = string
}

variable "docker_password" {
  description = "Docker registry password"
  type        = string
  sensitive   = true
}

# GitHub Info
variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub account or organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

# Deployment configuration values that tell GitHub Actions workflow which ECS resources to update.
variable "ecs_cluster_name" {
  description = "ecs cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ecs service name"
  type        = string
}

variable "ecs_task_family" {
  description = "ecs task family name"
  type        = string
}


# -----------------
# Environment variables to ECS Task Definition in the workflow
# Cognito + Redis (per env)
# ---------------------------

variable "cognito_region" {
  description = "AWS region for Cognito"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "cognito_app_client_id" {
  description = "Cognito App Client ID"
  type        = string
}

variable "cognito_app_public_client_id" {
  description = "Cognito Public App Client ID"
  type        = string
}

variable "cognito_app_client_secret" {
  description = "Cognito App Client Secret"
  type        = string
  sensitive   = true
}

variable "cognito_domain" {
  description = "Cognito domain URL"
  type        = string
}

variable "app_base_url" {
  description = "Base URL of the application"
  type        = string
}

variable "version_string" {
  description = "Application version string"
  type        = string
}
