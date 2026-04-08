variable "subnet_ids" {}
variable "security_group" {}
variable "db_name" {}
variable "username" {}

variable "password" {
  sensitive = true
}