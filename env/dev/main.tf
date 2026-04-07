module "vpc" {
  source = "../../modules/vpc"
}

module "sg" {
  source = "../../modules/security-group"
  vpc_id = module.vpc.vpc_id
}

module "alb" {
  source          = "../../modules/alb"
  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnets
  security_group  = module.sg.alb_sg
}

module "asg" {
  source             = "../../modules/asg"
  private_subnets    = module.vpc.private_subnets
  target_group_arn   = module.alb.target_group_arn
  security_group     = module.sg.app_sg
}

module "rds" {
  source          = "../../modules/rds"
  private_subnets = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id
  db_sg           = module.sg.db_sg
}