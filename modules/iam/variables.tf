variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARNs the ECS execution role may read"
  type        = list(string)
  default     = []
}
