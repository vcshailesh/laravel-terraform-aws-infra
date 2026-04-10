variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "db_username" {
  description = "Database username to store in the secret"
  type        = string
}

variable "db_password" {
  description = "Database password to store in the secret"
  type        = string
  sensitive   = true
}

variable "recovery_window_in_days" {
  description = "Number of days before a deleted secret is permanently removed"
  type        = number
  default     = 7
}
