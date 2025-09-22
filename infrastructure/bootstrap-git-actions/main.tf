terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

# GitHub Provider
provider "github" {
  token = var.github_token
  owner = var.github_owner
}

# AWS Provider
provider "aws" {
  # region     = var.aws_region
  region      = var.aws_region 
}

# -----------------
# Create AWS IAM User for GitHub Actions
# -----------------
resource "aws_iam_user" "gha_user" {
  name = "github-actions-deployer"
}

resource "aws_iam_user_policy_attachment" "ecs_access" {
  user       = aws_iam_user.gha_user.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_access_key" "gha_key" {
  user = aws_iam_user.gha_user.name
}

# -----------------
# Validate Docker Credentials
# -----------------
# resource "null_resource" "validate_docker_credentials" {
#   provisioner "local-exec" {
#     command = <<EOT
#       echo "${var.docker_password}" | docker login -u "${var.docker_username}" --password-stdin
#     EOT
#   }
# }

# -----------------
# Push AWS IAM Keys to GitHub Secrets
# -----------------
resource "github_actions_secret" "aws_access_key_id" {
  repository      = var.github_repo
  secret_name     = "AWS_ACCESS_KEY_ID"
  plaintext_value = aws_iam_access_key.gha_key.id
}

resource "github_actions_secret" "aws_secret_access_key" {
  repository      = var.github_repo
  secret_name     = "AWS_SECRET_ACCESS_KEY"
  plaintext_value = aws_iam_access_key.gha_key.secret
}

# -----------------
# Push Docker Credentials (only if valid)
# -----------------
resource "github_actions_secret" "docker_username" {
  repository      = var.github_repo
  secret_name     = "DOCKER_USERNAME"
  plaintext_value = var.docker_username
  # depends_on      = [null_resource.validate_docker_credentials]
}

resource "github_actions_secret" "docker_password" {
  repository      = var.github_repo
  secret_name     = "DOCKER_PASSWORD"
  plaintext_value = var.docker_password
  # depends_on      = [null_resource.validate_docker_credentials]
}

# -----------------
# Push deployment configuration values that tell GitHub Actions workflow which ECS resources to update.
# ECS Target
# -----------------
resource "github_actions_secret" "ecs_cluster_name" {
  repository      = var.github_repo
  secret_name     = "ECS_CLUSTER_NAME"
  plaintext_value = "btap-app4-dev-cluster"
}

resource "github_actions_secret" "ecs_service_name" {
  repository      = var.github_repo
  secret_name     = "ECS_SERVICE_NAME"
  plaintext_value = "btap-app4-dev-service"
}

resource "github_actions_secret" "ecs_task_family" {
  repository      = var.github_repo
  secret_name     = "ECS_TASK_FAMILY"
  plaintext_value = "btap-app4-dev-task"
}

# -----------------
# Environment variables to ECS Task Definition in the workflow
# Cognito + Redis (per env)
# ---------------------------

# === DEV ===
resource "github_actions_secret" "cognito_region" {
  repository      = var.github_repo
  secret_name     = "COGNITO_REGION"
  plaintext_value = var.cognito_region
}

resource "github_actions_secret" "cognito_user_pool_id" {
  repository      = var.github_repo
  secret_name     = "COGNITO_USER_POOL_ID"
  plaintext_value = var.cognito_user_pool_id
}

resource "github_actions_secret" "cognito_app_client_id" {
  repository      = var.github_repo
  secret_name     = "COGNITO_APP_CLIENT_ID"
  plaintext_value = var.cognito_app_client_id
}

resource "github_actions_secret" "cognito_app_public_client_id" {
  repository      = var.github_repo
  secret_name     = "COGNITO_APP_PUBLIC_CLIENT_ID"
  plaintext_value = var.cognito_app_public_client_id
}

resource "github_actions_secret" "cognito_app_client_secret" {
  repository      = var.github_repo
  secret_name     = "COGNITO_APP_CLIENT_SECRET"
  plaintext_value = var.cognito_app_client_secret
}

resource "github_actions_secret" "cognito_domain" {
  repository      = var.github_repo
  secret_name     = "COGNITO_DOMAIN"
  plaintext_value = var.cognito_domain
}

resource "github_actions_secret" "app_base_url" {
  repository      = var.github_repo
  secret_name     = "APP_BASE_URL"
  plaintext_value = var.app_base_url
}

resource "github_actions_secret" "version_string" {
  repository      = var.github_repo
  secret_name     = "VERSION_STRING"
  plaintext_value = var.version_string
}



