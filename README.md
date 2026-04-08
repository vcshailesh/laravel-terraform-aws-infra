# Terraform AWS Laravel Infra

Production-ready, fully modular AWS infrastructure for a Laravel application,
built with Terraform. Each concern is isolated into its own reusable module
and wired together per environment under `env/`.

---

## Architecture

```
Internet
    │  (port 80 / 443)
    ▼
┌─────────────────────────────────┐
│  Application Load Balancer      │  ← public subnets
│  (ALB + HTTPS-ready listener)   │
└───────────────┬─────────────────┘
                │  (port 80, target_type = ip)
    ▼
┌─────────────────────────────────┐
│  ECS Fargate Service            │  ← private subnets
│  (Laravel container, awsvpc)    │
└───────────────┬─────────────────┘
                │  (port 3306)
    ▼
┌─────────────────────────────────┐
│  RDS MySQL 8.0                  │  ← private subnets
└─────────────────────────────────┘
```

### Modules

| Module | Path | Responsibility |
|---|---|---|
| `vpc` | `modules/vpc` | VPC, public/private subnets, IGW, route tables |
| `security-group` | `modules/security-group` | ALB, App, and RDS security groups |
| `alb` | `modules/alb` | Application Load Balancer, target group, listener |
| `ecr` | `modules/ecr` | ECR repository with image scanning |
| `iam` | `modules/iam` | ECS execution role + task role with managed policies |
| `ecs` | `modules/ecs` | ECS cluster, Fargate task definition, service |
| `rds` | `modules/rds` | RDS MySQL instance and subnet group |

### Environments

| Environment | Path |
|---|---|
| `dev` | `env/dev` |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- An S3 bucket and DynamoDB table for remote state (see `env/dev/backend.tf`)
- A container image pushed to ECR (see `modules/ecr`)

---

## Remote State

State is stored in S3 with DynamoDB locking. Update `env/dev/backend.tf` with
your bucket name and table before running `terraform init`:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "dev/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "terraform-lock"
}
```

---

## Deploy

### 1. Supply the database password securely

Never commit the password to source control. Pass it as an environment variable:

```bash
export TF_VAR_db_password="your-secure-password"
```

### 2. Initialise and apply

```bash
cd env/dev

terraform init
terraform plan
terraform apply
```

### Variables (`env/dev/terraform.tfvars`)

| Variable | Description | Default |
|---|---|---|
| `region` | AWS region | `ap-south-1` |
| `image_url` | Full ECR image URI | — |
| `db_name` | RDS database name | — |
| `db_user` | RDS master username | — |
| `db_password` | RDS master password *(sensitive)* | — |

---

## Security Notes

- The **App SG** only accepts inbound traffic from the ALB SG — no public
  access to containers.
- The **RDS SG** only accepts inbound traffic from the App SG — database is
  never publicly exposed.
- The **ECS execution role** is granted only
  `AmazonECSTaskExecutionRolePolicy` — least-privilege for ECR pulls and
  CloudWatch Logs.
- `db_password` is marked `sensitive = true` in Terraform and must be
  supplied via `TF_VAR_db_password` — never stored in `terraform.tfvars`.

---

## Destroying

```bash
cd env/dev
terraform destroy
```