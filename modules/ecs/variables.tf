variable "cluster_name" {}
variable "image_url" {}
variable "private_subnets" {}
variable "security_group_id" {}
variable "execution_role_arn" {}
variable "task_role_arn" {}
variable "target_group_arn" {}
variable "listener" {}

variable "aws_region" {
  default = "ap-south-1"
}