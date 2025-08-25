# This variable defines the main name for your project or application.
# All other names will be derived from this.
variable "project_name" {
  type        = string
  description = "The base name for the project or application (e.g., 'myapp'). Used to prefix all resources."
  default     = "btap-app" # A sensible default value
}

# This variable defines the environment (e.g., dev, staging, prod).
variable "environment" {
  type        = string
  description = "The deployment environment (e.g., 'dev', 'staging', 'prod')."
  default     = "dev"
}

# You can add other configurable parameters here too
variable "instance_type" {
  type        = string
  description = "The EC2 instance type for the ECS container instances."
  default     = "t3.small"
}