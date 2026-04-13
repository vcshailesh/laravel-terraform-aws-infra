variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "image_url" {
  description = "Full container image URI (e.g. 123456789.dkr.ecr.region.amazonaws.com/app:tag)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch log group"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the ALB target group"
  type        = string
}

variable "http_listener_arn" {
  description = "ARN of the ALB HTTP listener (used for depends_on)"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "cpu" {
  description = "CPU units for the Fargate task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory (MiB) for the Fargate task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of running tasks"
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum number of tasks for autoscaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks for autoscaling"
  type        = number
  default     = 6
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for autoscaling"
  type        = number
  default     = 70
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights on the cluster"
  type        = bool
  default     = true
}

# ── Database configuration ──────────────────────

variable "db_host" {
  description = "RDS instance hostname"
  type        = string
}

variable "db_port" {
  description = "RDS instance port"
  type        = number
  default     = 3306
}

variable "db_name" {
  description = "Name of the database"
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials (JSON with 'username' and 'password' keys)"
  type        = string
}

# ── Application configuration ───────────────────

variable "app_key" {
  description = "Laravel APP_KEY for encryption"
  type        = string
  sensitive   = true
}

variable "app_url" {
  description = "Public URL of the application (ALB DNS or custom domain)"
  type        = string
  default     = ""
}

variable "enable_migrations" {
  description = "Run database migrations on container startup"
  type        = bool
  default     = true
}
