locals {
  project     = "laravel"
  environment = "dev"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terraform"
  }

  availability_zones = ["${var.region}a", "${var.region}b"]
}
