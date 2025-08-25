# This Terraform configuration bootstraps the backend resources.
# It now accepts variables for all names.

# --- Variable Definitions ---
variable "aws_region" {
  type        = string
  description = "The AWS region where backend resources will be deployed."
}

variable "s3_bucket_name" {
  type        = string
  description = "The globally unique name for the S3 bucket."
}

variable "dynamodb_table_name" {
  type        = string
  description = "The name for the DynamoDB table for state locking."
}

# --- Provider ---
provider "aws" {
  region = var.aws_region
}

# --- Resources ---
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.s3_bucket_name
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_public_access" {
  bucket = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  lifecycle {
    prevent_destroy = true
  }
}