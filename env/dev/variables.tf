variable "region" {
  default = "ap-south-1"
}

variable "image_url" {}

variable "db_name" {}

variable "db_user" {}

variable "db_password" {
  sensitive = true
}