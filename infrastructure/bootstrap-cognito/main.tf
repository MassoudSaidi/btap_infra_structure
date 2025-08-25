# Use variables for environment-specific values
variable "app_name" {
  description = "The name of the application."
  type        = string
  default     = "my-app"
}

variable "app_environment" {
  description = "The environment for the deployment (e.g., 'dev', 'staging', 'prod')."
  type        = string
  default     = "dev"
}

variable "cognito_callback_urls" {
  description = "A list of allowed callback URLs for the Cognito app client."
  type        = list(string)
  default     = ["http://localhost:3000/auth/callback"]
}

variable "cognito_logout_urls" {
  description = "A list of allowed logout URLs for the Cognito app client."
  type        = list(string)
  default     = ["http://localhost:3000/logout"]
}

variable "cognito_public_callback_urls" {
  description = "A list of allowed callback URLs for the Cognito public app."
  type        = list(string)
  default     = ["https://oauth.pstmn.io/v1/callback", "http://localhost:3000/docs/oauth2-redirect"]
}

variable "cognito_public_logout_urls" {
  description = "A list of allowed logout URLs for the Cognito app client."
  type        = list(string)
  default     = ["http://localhost:3000/docs"]
}

# Create a unique domain name
locals {
  cognito_domain = "${var.app_name}-${var.app_environment}-auth"
}

# --------------------------------------------------------------------------------
# NEW: IAM Role for the Pre-Token Generation Lambda Function
# --------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_pre_token_role" {
  name = "${var.app_name}-${var.app_environment}-pre-token-lambda-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_pre_token_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --------------------------------------------------------------------------------
# NEW: Lambda Function to Add Groups to ID Token
# --------------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "cognito_add_groups_to_token" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.app_name}-${var.app_environment}-add-groups-to-token"
  role             = aws_iam_role.lambda_pre_token_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.9"

  tags = {
    Name        = "${var.app_name}-${var.app_environment}-add-groups-lambda"
    Environment = var.app_environment
  }
}

# --------------------------------------------------------------------------------
# MODIFIED: Cognito User Pool with Lambda Trigger
# --------------------------------------------------------------------------------
resource "aws_cognito_user_pool" "main" {
  name = "${var.app_name}-${var.app_environment}-user-pool"

  # ... other attributes like password_policy ...

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  # SECURITY: Enable MFA
  mfa_configuration = "OPTIONAL" # This stays the same

  # FIX: Add this block to enable authenticator apps (TOTP)
  software_token_mfa_configuration {
    enabled = true
  }

  # --- MODIFICATION: Add Lambda trigger configuration ---
  lambda_config {
    pre_token_generation = aws_lambda_function.cognito_add_groups_to_token.arn
  }
  # --- End of Modification ---

  tags = {
    Name        = "${var.app_name}-${var.app_environment}-user-pool"
    Environment = var.app_environment
  }
}

# --------------------------------------------------------------------------------
# NEW: Lambda Permission for Cognito Invocation
# --------------------------------------------------------------------------------
resource "aws_lambda_permission" "cognito_allow_invoke_lambda" {
  statement_id  = "AllowCognitoToInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cognito_add_groups_to_token.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}


# A separate client for Swagger & Postman testing
resource "aws_cognito_user_pool_client" "surrogate_public_client" {
  name                                 = "${var.app_name}-${var.app_environment}-public-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false # << no secret
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.cognito_public_callback_urls
  logout_urls                          = var.cognito_public_logout_urls
  supported_identity_providers         = ["COGNITO"]

  prevent_user_existence_errors = "ENABLED"
  # Enable explicit auth flows for direct user auth
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${var.app_name}-${var.app_environment}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = true

  # SECURITY: Avoid the 'implicit' flow
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.cognito_callback_urls
  logout_urls                          = var.cognito_logout_urls
  supported_identity_providers         = ["COGNITO"]

  # SECURITY: Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = local.cognito_domain
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_group" "free_tier" {
  name         = "Free-Tier"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Group for users on the free tier with basic rate limits."
  precedence   = 100
}

resource "aws_cognito_user_group" "researcher_tier" {
  name         = "Researcher-Tier"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Group for users on the Researcher tier with higher rate limits."
  precedence   = 80
}

resource "aws_cognito_user_group" "developer_tier" {
  name         = "Developer-Tier"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Group for users on the Developer tier with higher rate limits."
  precedence   = 20
}

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.app.id
}

output "public_client_id" {
  value = aws_cognito_user_pool_client.surrogate_public_client.id
}

# FIX & SECURITY: Correctly reference the client secret and mark it as sensitive.
output "client_secret" {
  description = "The Client Secret for the Cognito App Client. This is a sensitive value."
  value       = aws_cognito_user_pool_client.app.client_secret
  sensitive   = true # This is CRITICAL for security.
}

output "domain" {
  value = aws_cognito_user_pool_domain.domain.domain
}