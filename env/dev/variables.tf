variable "aws_profile" {
  description = "AWS CLI named profile to use for authentication"
  type        = string
  default     = "shailesh-aws"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "image_url" {
  description = "Full ECR image URI (e.g. 123456789.dkr.ecr.ap-south-1.amazonaws.com/laravel-app:latest)"
  type        = string
}

variable "db_name" {
  description = "Name of the RDS database to create"
  type        = string
}

variable "db_user" {
  description = "Master username for the RDS instance"
  type        = string
}

variable "db_password" {
  description = "Master password for the RDS instance — supply via TF_VAR_db_password"
  type        = string
  sensitive   = true
}
