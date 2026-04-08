provider "aws" {
  region = var.region
}

# -------------------
# VPC
# -------------------
module "vpc" {
  source = "../../modules/vpc"
}

# -------------------
# SECURITY GROUPS
# -------------------
module "sg" {
  source = "../../modules/security-group"
  vpc_id = module.vpc.vpc_id
}

# -------------------
# ECR
# -------------------
module "ecr" {
  source = "../../modules/ecr"
}

# -------------------
# IAM (ECS ROLES)
# -------------------
module "iam" {
  source = "../../modules/iam"
}

# -------------------
# ALB
# -------------------
module "alb" {
  source            = "../../modules/alb"
  vpc_id            = module.vpc.vpc_id
  public_subnets    = module.vpc.public_subnets
  security_group_id = module.sg.alb_sg
}

# -------------------
# RDS
# -------------------
module "rds" {
  source         = "../../modules/rds"
  subnet_ids     = module.vpc.private_subnets
  db_name        = var.db_name
  username       = var.db_user
  password       = var.db_password
  security_group = module.sg.rds_sg
}

# -------------------
# ECS (CORE)
# -------------------
module "ecs" {
  source = "../../modules/ecs"

  cluster_name       = "laravel-dev"
  image_url          = var.image_url
  aws_region         = var.region
  private_subnets    = module.vpc.private_subnets
  security_group_id  = module.sg.app_sg

  execution_role_arn = module.iam.ecs_execution_role
  task_role_arn      = module.iam.ecs_task_role

  target_group_arn   = module.alb.target_group_arn
  listener           = module.alb.listener
}