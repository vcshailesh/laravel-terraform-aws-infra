# ───────────────────────────────────────────────
# VPC
# ───────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  project            = local.project
  environment        = local.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = local.availability_zones
  enable_nat_gateway = true
  single_nat_gateway = true
  enable_flow_logs   = false
}

# ───────────────────────────────────────────────
# Security Groups
# ───────────────────────────────────────────────

module "sg" {
  source = "../../modules/security-group"

  project     = local.project
  environment = local.environment
  vpc_id      = module.vpc.vpc_id
}

# ───────────────────────────────────────────────
# ECR
# ───────────────────────────────────────────────

module "ecr" {
  source = "../../modules/ecr"

  project         = local.project
  environment     = local.environment
  repository_name = "laravel-app"
}

# ───────────────────────────────────────────────
# IAM (ECS Roles)
# ───────────────────────────────────────────────

module "iam" {
  source = "../../modules/iam"

  project     = local.project
  environment = local.environment
}

# ───────────────────────────────────────────────
# ALB
# ───────────────────────────────────────────────

module "alb" {
  source = "../../modules/alb"

  project                    = local.project
  environment                = local.environment
  vpc_id                     = module.vpc.vpc_id
  public_subnets             = module.vpc.public_subnets
  security_group_id          = module.sg.alb_sg
  health_check_path          = "/up"
  enable_deletion_protection = false
}

# ───────────────────────────────────────────────
# RDS
# ───────────────────────────────────────────────

module "rds" {
  source = "../../modules/rds"

  project     = local.project
  environment = local.environment

  subnet_ids     = module.vpc.private_subnets
  security_group = module.sg.rds_sg
  db_name        = var.db_name
  username       = var.db_user
  password       = var.db_password

  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  storage_encrypted   = true
  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true
}

# ───────────────────────────────────────────────
# Secrets Manager
# ───────────────────────────────────────────────

module "secrets" {
  source = "../../modules/secrets"

  project     = local.project
  environment = local.environment
  db_username = var.db_user
  db_password = var.db_password
}

# ───────────────────────────────────────────────
# ECS (Fargate)
# ───────────────────────────────────────────────

module "ecs" {
  source = "../../modules/ecs"

  project     = local.project
  environment = local.environment

  cluster_name      = "${local.project}-${local.environment}"
  image_url         = var.image_url
  aws_region        = var.region
  private_subnets   = module.vpc.private_subnets
  security_group_id = module.sg.app_sg

  execution_role_arn = module.iam.ecs_execution_role
  task_role_arn      = module.iam.ecs_task_role

  target_group_arn  = module.alb.target_group_arn
  http_listener_arn = module.alb.http_listener_arn

  cpu                = 256
  memory             = 512
  desired_count      = 2
  min_capacity       = 1
  max_capacity       = 4
  log_retention_days = 7
}

# ───────────────────────────────────────────────
# Monitoring
# ───────────────────────────────────────────────

module "monitoring" {
  source = "../../modules/monitoring"

  project     = local.project
  environment = local.environment

  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name

  enable_rds_alarms = true
  rds_instance_id   = module.rds.identifier
}
