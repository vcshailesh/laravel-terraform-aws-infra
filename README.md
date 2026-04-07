# Terraform AWS Laravel Infra

Production-ready AWS infrastructure using Terraform.

## Architecture
- VPC (public + private subnets)
- ALB
- Auto Scaling EC2
- RDS MySQL

## Deploy

cd env/dev
terraform init
terraform apply