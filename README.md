# Terraform AWS Laravel Infrastructure

Production-ready, fully modular AWS infrastructure for a Laravel application
running on ECS Fargate, managed entirely with Terraform.

---

## TL;DR

```bash
# 1. Bootstrap remote state (one-time)
./scripts/bootstrap-state.sh my-terraform-bucket ap-south-1 terraform-lock

# 2. Set up your variables
cp env/dev/terraform.tfvars.example env/dev/terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Export secrets
export TF_VAR_db_password="YourSecureP@ssw0rd"
export TF_VAR_app_key="base64:YOUR_LARAVEL_APP_KEY"

# 4. Deploy everything (infra + Docker build + ECR push + ECS redeploy)
./scripts/deploy.sh dev latest

# 5. Open your app
cd env/dev && terraform output alb_dns_name

# Tear down when done
./scripts/destroy.sh dev
```

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

---

## Project Structure

```
.
├── env/
│   └── dev/                    # Development environment root module
│       ├── backend.tf          # S3 remote state config
│       ├── locals.tf           # Common tags & computed values
│       ├── main.tf             # Module composition
│       ├── outputs.tf          # Stack outputs
│       ├── providers.tf        # AWS provider config
│       ├── variables.tf        # Input variables
│       ├── versions.tf         # Terraform + provider versions
│       └── terraform.tfvars.example
├── modules/
│   ├── alb/                    # Application Load Balancer + target group
│   ├── ecr/                    # ECR repository + lifecycle policy
│   ├── ecs/                    # Fargate cluster, task def, service, autoscaling
│   ├── iam/                    # ECS execution & task roles
│   ├── monitoring/             # CloudWatch alarms (ECS + RDS)
│   ├── rds/                    # RDS MySQL (encrypted, backups)
│   ├── secrets/                # Secrets Manager for DB credentials
│   ├── security-group/         # ALB, App, RDS security groups
│   └── vpc/                    # VPC, subnets, NAT, IGW, route tables
├── laravel-app/                # Laravel application + Dockerfile
│   ├── Dockerfile              # Multi-stage PHP 8.3 + Nginx + Supervisor
│   ├── docker/
│   │   ├── entrypoint.sh       # Caches config, runs migrations
│   │   ├── nginx.conf
│   │   └── supervisord.conf
│   └── docker-compose.yml      # Local development stack
├── scripts/
│   ├── bootstrap-state.sh      # Create S3 bucket + DynamoDB lock table
│   ├── validate.sh             # Lint, format check, module validation
│   ├── deploy.sh               # Full deploy: Terraform + Docker + ECR + ECS
│   ├── push-ecr.sh             # Build & push Docker image to ECR
│   └── destroy.sh              # Tear down all resources
├── global/                     # Cross-environment resources (Route53, ACM — planned)
└── .github/workflows/
    ├── terraform.yml           # PR: plan → comment | Push to main: apply
    └── deploy.yml              # Push to main: build image → ECR → ECS redeploy
```

---

## Modules

| Module | Path | What it does |
|--------|------|-------------|
| **vpc** | `modules/vpc` | VPC, 2-AZ public/private subnets, IGW, NAT Gateway, route tables, optional VPC Flow Logs |
| **security-group** | `modules/security-group` | ALB, App, and RDS security groups with least-privilege ingress/egress |
| **alb** | `modules/alb` | Application Load Balancer, target group (ip), HTTP listener, health check on `/up` |
| **ecr** | `modules/ecr` | ECR repository with scan-on-push and image lifecycle policy |
| **iam** | `modules/iam` | ECS execution role (pulls images, reads secrets) + task role |
| **ecs** | `modules/ecs` | ECS cluster (Container Insights), Fargate task definition, service with circuit breaker, autoscaling (1–4 tasks), CloudWatch log group |
| **rds** | `modules/rds` | RDS MySQL 8.0 — encrypted at rest, configurable multi-AZ, backups, deletion protection |
| **secrets** | `modules/secrets` | Secrets Manager secret for DB username/password, consumed by ECS task via ARN |
| **monitoring** | `modules/monitoring` | CloudWatch alarms — ECS CPU high, ECS memory high, RDS CPU high, RDS free storage low |

---

## Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | ~> 1.5 | `terraform -version` |
| [AWS CLI](https://aws.amazon.com/cli/) | >= 2 | `aws --version` |
| [Docker](https://docs.docker.com/get-docker/) | >= 24 | `docker --version` |

You also need an AWS account with permissions for: VPC, EC2, ECS, ECR, RDS, ALB,
CloudWatch, Secrets Manager, IAM, S3, DynamoDB.

---

## Quick Start (Step by Step)

### 1. Bootstrap Remote State (one-time)

Create the S3 bucket and DynamoDB table that Terraform uses for state locking:

```bash
./scripts/bootstrap-state.sh <BUCKET_NAME> <REGION> <TABLE_NAME>

# Example:
./scripts/bootstrap-state.sh laravel-tfstate-123456 ap-south-1 terraform-lock
```

Then update `env/dev/backend.tf` with the bucket name and table if you used custom values.

### 2. Configure Variables

```bash
cp env/dev/terraform.tfvars.example env/dev/terraform.tfvars
```

Edit `env/dev/terraform.tfvars`:

```hcl
aws_profile = "your-aws-profile"
region      = "ap-south-1"
image_url   = "ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/laravel-app:latest"
db_name     = "laravel"
db_user     = "admin"
```

### 3. Export Sensitive Variables

Never commit secrets. Pass them as environment variables:

```bash
export TF_VAR_db_password="YourSecureP@ssw0rd"
export TF_VAR_app_key="base64:YOUR_LARAVEL_APP_KEY"
```

Generate an app key with `php artisan key:generate --show` if you don't have one.

### 4. Validate (optional but recommended)

```bash
./scripts/validate.sh
```

Runs format checks, module HCL validation, and file structure verification.

### 5. Deploy

**Option A — One command (recommended):**

```bash
./scripts/deploy.sh dev latest
```

This will: Terraform init/apply → Docker build → ECR push → ECS force redeploy.

**Option B — Step by step:**

```bash
cd env/dev
terraform init
terraform plan
terraform apply

# Push the Docker image
cd ../..
./scripts/push-ecr.sh latest

# Force ECS to pick up the new image
aws ecs update-service \
  --cluster laravel-dev \
  --service laravel-dev-service \
  --force-new-deployment \
  --region ap-south-1
```

### 6. Verify

```bash
cd env/dev
ALB_DNS=$(terraform output -raw alb_dns_name)

# Wait 2-3 minutes for ECS tasks to start
curl -I http://${ALB_DNS}/up     # Should return 200
curl    http://${ALB_DNS}/       # Laravel welcome page
```

---

## Variables

| Variable | Description | Default | Sensitive |
|----------|-------------|---------|-----------|
| `aws_profile` | AWS CLI named profile | `shailesh-aws` | No |
| `region` | AWS region | `ap-south-1` | No |
| `image_url` | Full ECR image URI | — (required) | No |
| `db_name` | RDS database name | — (required) | No |
| `db_user` | RDS master username | — (required) | No |
| `db_password` | RDS master password | — (required) | **Yes** |
| `app_key` | Laravel `APP_KEY` | — (required) | **Yes** |

Sensitive variables should be supplied via `TF_VAR_*` environment variables.

## Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | ID of the VPC |
| `alb_dns_name` | DNS name to reach the application |
| `ecr_repository_url` | ECR image push target |
| `ecs_cluster_name` | ECS cluster identifier |
| `ecs_service_name` | ECS service identifier |
| `rds_endpoint` | RDS connection string |
| `nat_gateway_ips` | NAT Gateway public IPs |

---

## Scripts

| Script | Usage | What it does |
|--------|-------|-------------|
| `bootstrap-state.sh` | `./scripts/bootstrap-state.sh [BUCKET] [REGION] [TABLE]` | Creates S3 bucket (versioned, encrypted) + DynamoDB lock table |
| `validate.sh` | `./scripts/validate.sh` | Runs `fmt -check`, validates all modules, checks file structure |
| `deploy.sh` | `./scripts/deploy.sh [ENV] [TAG]` | Full pipeline: Terraform apply → Docker build → ECR push → ECS redeploy |
| `push-ecr.sh` | `./scripts/push-ecr.sh [TAG]` | Build and push the Docker image to ECR |
| `destroy.sh` | `./scripts/destroy.sh [ENV]` | Destroy all Terraform resources (with safety prompt for staging/prod) |

All scripts default to the `dev` environment and `ap-south-1` region.

---

## Docker Image

The Laravel application lives in `laravel-app/` with a multi-stage Dockerfile:

- **Base**: PHP 8.3 FPM Alpine + Nginx + Supervisor
- **Deps**: Composer install (cached layer)
- **Production**: Optimized autoloader, OPcache enabled, JIT compilation

The entrypoint (`docker/entrypoint.sh`) automatically:
1. Caches Laravel config, routes, and views
2. Runs database migrations if `RUN_MIGRATIONS=true` (controlled via Terraform's `enable_migrations` variable)

### Local Testing with Docker Compose

```bash
cd laravel-app
docker compose up --build -d
docker compose exec app php artisan migrate --force
curl http://localhost:8080/up     # Health check
docker compose down -v
```

---

## CI/CD (GitHub Actions)

### Terraform Pipeline — `.github/workflows/terraform.yml`

| Trigger | Steps |
|---------|-------|
| PR → `main` | `fmt -check` → `init` → `validate` → `plan` (posted as PR comment) |
| Push → `main` | `fmt -check` → `init` → `validate` → `plan` → `apply` |

### Deploy Pipeline — `.github/workflows/deploy.yml`

On every push to `main`: build Docker image → tag with git SHA + `latest` → push to ECR → force ECS redeployment.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM access key with ECR/ECS/Terraform permissions |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret key |
| `TF_VAR_DB_PASSWORD` | RDS master password |

---

## Security

- **Network isolation** — App containers accept traffic only from the ALB security group; RDS accepts only from the App security group. No public database access.
- **Encryption at rest** — RDS `storage_encrypted = true`. ECR images scanned on push.
- **Private subnets** — ECS tasks and RDS run in private subnets. Outbound via NAT Gateway for ECR pulls.
- **Least-privilege IAM** — Execution role scoped to ECR pull + CloudWatch Logs + Secrets Manager read.
- **Secrets Manager** — DB credentials stored in Secrets Manager, injected into containers at runtime (never in env vars or Terraform state).
- **Sensitive variables** — `db_password` and `app_key` are `sensitive = true`; must be supplied via `TF_VAR_*`.
- **Deployment safety** — ECS circuit breaker with automatic rollback enabled.
- **Deletion protection** — Configurable per environment; recommended `true` for staging/prod.

---

## Tagging

All resources are tagged with:

| Tag | Value |
|-----|-------|
| `Project` | `laravel` |
| `Environment` | `dev` / `staging` / `prod` |
| `ManagedBy` | `terraform` |

Resource-specific `Name` tags follow `<project>-<environment>-<component>`.

---

## Monitoring

CloudWatch alarms are created by the `monitoring` module:

| Alarm | Condition |
|-------|-----------|
| ECS CPU High | CPU > 80% for 2 consecutive periods |
| ECS Memory High | Memory > 80% for 2 consecutive periods |
| RDS CPU High | CPU > 80% for 2 consecutive periods |
| RDS Free Storage Low | Free storage < 5 GB |

View alarm status:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix laravel-dev \
  --region ap-south-1 \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}'
```

Tail ECS logs:

```bash
aws logs tail /ecs/laravel-dev --follow --region ap-south-1
```

---

## Adding a New Environment

```bash
cp -r env/dev env/prod

# Edit these files in env/prod/:
#   backend.tf   → change state key to "prod/terraform.tfstate"
#   locals.tf    → set environment = "prod"
#   main.tf      → adjust instance sizes, enable multi_az, deletion_protection, etc.
#   terraform.tfvars from the example

cd env/prod && terraform init && terraform plan
```

---

## Destroying

```bash
# Destroy dev environment
./scripts/destroy.sh dev

# Staging/prod will prompt for confirmation
./scripts/destroy.sh prod
```

To also remove the state backend:

```bash
aws s3 rb s3://your-terraform-state-bucket --force
aws dynamodb delete-table --table-name terraform-lock --region ap-south-1
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| ECS tasks keep restarting | Image can't reach ECR | Verify NAT Gateway exists, check SG egress |
| ALB health check failing | `/up` returns non-200 | Check `APP_KEY` is set, check ECS logs |
| RDS connection refused | SG or subnet mismatch | Verify App SG → RDS SG rule, same VPC |
| Terraform plan shows 0 changes but app won't start | Old image cached | Force redeploy: `./scripts/deploy.sh dev latest` |
| `docker build` fails on composer | Missing `composer.lock` | Run `composer install` locally first |

---

## Further Reading

- [TESTING.md](TESTING.md) — Full end-to-end testing guide (local Docker Compose + AWS deployment)
- [AGENTS.md](AGENTS.md) — AI agent coding standards and project conventions
