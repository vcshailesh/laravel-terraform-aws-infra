# Terraform AWS Laravel Infrastructure

Production-ready, fully modular AWS infrastructure for a Laravel application
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
│  (HTTP listener, HTTPS-ready)   │
└───────────────┬─────────────────┘
                │  (target_type = ip)
                ▼
┌─────────────────────────────────┐
│  ECS Fargate Service            │  ← private subnets
│  (Laravel container, awsvpc)    │
│  Auto Scaling (CPU target)      │
└───────────────┬─────────────────┘
                │  (port 3306)
                ▼
┌─────────────────────────────────┐
│  RDS MySQL 8.0 (encrypted)      │  ← private subnets
└─────────────────────────────────┘

Private subnet outbound: NAT Gateway → Internet Gateway
```

### Modules

| Module | Path | Responsibility |
|---|---|---|
| `vpc` | `modules/vpc` | VPC, public/private subnets, IGW, NAT Gateway, route tables, optional VPC Flow Logs |
| `security-group` | `modules/security-group` | ALB, App, and RDS security groups with least-privilege rules |
| `alb` | `modules/alb` | Application Load Balancer, target group, HTTP listener |
| `ecr` | `modules/ecr` | ECR repository with image scanning and lifecycle policy |
| `iam` | `modules/iam` | ECS execution role + task role with managed policies |
| `ecs` | `modules/ecs` | ECS cluster (Container Insights), Fargate task, service, autoscaling, circuit breaker |
| `rds` | `modules/rds` | RDS MySQL with encryption, backups, optional multi-AZ and Performance Insights |
| `monitoring` | `modules/monitoring` | CloudWatch alarms for ECS (CPU, memory) and RDS (CPU, storage) |
| `secrets` | `modules/secrets` | Secrets Manager for RDS credentials |

### Environments

| Environment | Path | Status |
|---|---|---|
| `dev` | `env/dev` | Active |
| `staging` | `env/staging` | Planned |
| `prod` | `env/prod` | Planned |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ~> 1.5
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- An S3 bucket and DynamoDB table for remote state (see `env/dev/backend.tf`)
- A container image pushed to ECR

---

## Remote State

State is stored in S3 with DynamoDB locking and encryption. Update
`env/dev/backend.tf` with your bucket name and table before running
`terraform init`:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "dev/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "terraform-lock"
  encrypt        = true
}
```

---

## Deploy (Local)

### 1. Create your local var file

```bash
cp env/dev/terraform.tfvars.example env/dev/terraform.tfvars
# Edit terraform.tfvars with your image URL, db_name, and db_user
```

### 2. Supply the database password securely

Never commit the password to source control. Pass it as an environment variable:

```bash
export TF_VAR_db_password="your-secure-password"
```

### 3. Initialise and apply

```bash
cd env/dev
terraform init
terraform plan
terraform apply
```

### Variables

| Variable | Description | Default |
|---|---|---|
| `region` | AWS region | `ap-south-1` |
| `image_url` | Full ECR image URI | — |
| `db_name` | RDS database name | — |
| `db_user` | RDS master username | — |
| `db_password` | RDS master password *(sensitive)* | — |

### Outputs

| Output | Description |
|---|---|
| `alb_dns_name` | DNS name to reach the application |
| `ecr_repository_url` | ECR image push target |
| `ecs_cluster_name` | ECS cluster identifier |
| `rds_endpoint` | RDS connection string |
| `nat_gateway_ips` | NAT Gateway public IPs |

---

## CI/CD (GitHub Actions)

Two workflows run automatically on push/PR to `main`:

### `.github/workflows/terraform.yml` — Terraform

| Trigger | Steps |
|---|---|
| Pull Request → `main` | `fmt -check` → `init` → `validate` → `plan` (posted as PR comment) |
| Push → `main` | `fmt -check` → `init` → `validate` → `plan` → `apply` |

### `.github/workflows/deploy.yml` — Docker Build & ECR Push

Builds the Laravel Docker image, tags it with the git SHA, pushes to ECR,
and triggers an ECS service redeployment on every push to `main`.

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM access key with ECR/ECS/RDS permissions |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret key |
| `TF_VAR_DB_PASSWORD` | RDS master password (used by Terraform workflow) |

---

## Security

- **Network isolation**: App containers accept traffic only from the ALB SG;
  RDS accepts traffic only from the App SG. No public database access.
- **Encryption at rest**: RDS `storage_encrypted = true`. ECR images scanned on push.
- **NAT Gateway**: Private subnet outbound for ECR pulls and external APIs —
  containers are never directly exposed.
- **Least-privilege IAM**: Execution role limited to `AmazonECSTaskExecutionRolePolicy`.
- **Secrets Manager**: RDS credentials stored in Secrets Manager, not in Terraform state.
- **Sensitive variables**: `db_password` is `sensitive = true` and must be
  supplied via `TF_VAR_db_password`.
- **Deletion protection**: Configurable per environment; recommended `true` for staging/prod.
- **Deployment safety**: ECS circuit breaker with automatic rollback enabled.

---

## Tagging

All resources are tagged with:

| Tag | Value |
|---|---|
| `Project` | `laravel` |
| `Environment` | `dev` / `staging` / `prod` |
| `ManagedBy` | `terraform` |

Resource-specific `Name` tags follow the pattern `<project>-<environment>-<component>`.

---

## Adding a New Environment

```bash
cp -r env/dev env/prod
# Edit env/prod/backend.tf  → change state key to "prod/terraform.tfstate"
# Edit env/prod/locals.tf   → set environment = "prod"
# Edit env/prod/main.tf     → adjust instance sizes, enable multi_az, deletion_protection, etc.
# Create env/prod/terraform.tfvars from the example
cd env/prod && terraform init && terraform plan
```

---

## Destroying

```bash
cd env/dev
terraform destroy
```
