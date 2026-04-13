# Testing Guide

End-to-end testing for this Terraform + Laravel infrastructure.
Two paths: **Local** (Docker Compose, no AWS needed) and **AWS** (full ECS Fargate deployment).

---

## TL;DR — Local Only

```bash
cd laravel-app
docker compose up --build -d        # Builds app + MySQL, runs migrations automatically
curl http://localhost:8080/up        # Health check → 200
curl http://localhost:8080/          # Laravel welcome page
docker compose down -v               # Tear down
```

## TL;DR — Full AWS Deploy

```bash
# One-time: bootstrap state backend
./scripts/bootstrap-state.sh my-tf-bucket ap-south-1 terraform-lock

# Configure
cp env/dev/terraform.tfvars.example env/dev/terraform.tfvars
# Edit terraform.tfvars

# Export secrets
export TF_VAR_db_password="YourSecureP@ssw0rd"
export TF_VAR_app_key="base64:$(php artisan key:generate --show | sed 's/base64://')"

# Deploy everything
./scripts/deploy.sh dev latest

# Verify
ALB=$(cd env/dev && terraform output -raw alb_dns_name)
curl -I http://$ALB/up               # → 200

# Tear down
./scripts/destroy.sh dev
```

---

## Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| Docker | >= 24 | `docker --version` |
| Docker Compose | >= 2 | `docker compose version` |
| Terraform | ~> 1.5 | `terraform -version` |
| AWS CLI | >= 2 | `aws --version` |
| PHP *(optional, for key generation)* | >= 8.3 | `php -v` |

---

## Step 1 — Test Locally with Docker Compose

The Laravel app is already in `laravel-app/` with a `docker-compose.yml` that spins up the app + MySQL 8.0.

```bash
cd laravel-app
docker compose up --build -d
```

**What happens automatically:**
- MySQL starts with a health check (retries until ready)
- App container waits for MySQL via `depends_on: condition: service_healthy`
- Entrypoint caches config/routes/views, then runs `php artisan migrate --force`

**Verify:**

```bash
# Health check (ALB uses this in production)
curl http://localhost:8080/up
# → 200 OK

# Home page
curl -I http://localhost:8080/
# → 200

# Check logs if something is wrong
docker compose logs -f app
```

**Tear down:**

```bash
docker compose down -v
cd ..
```

If this works, your Docker image is production-ready. Proceed to AWS deployment.

---

## Step 2 — Configure AWS Credentials

```bash
# Option A: Named profile (recommended)
aws configure --profile your-profile
export AWS_PROFILE=your-profile

# Option B: Environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="ap-south-1"

# Verify access
aws sts get-caller-identity
```

**Required IAM permissions:** VPC, EC2, ECS, ECR, RDS, ALB, CloudWatch, Secrets Manager, IAM, S3, DynamoDB.

---

## Step 3 — Bootstrap Terraform State Backend

The S3 bucket and DynamoDB lock table must exist before `terraform init`:

```bash
./scripts/bootstrap-state.sh <BUCKET_NAME> <REGION> <TABLE_NAME>
```

**Example:**

```bash
./scripts/bootstrap-state.sh laravel-tfstate-123456 ap-south-1 terraform-lock
```

The script creates:
- S3 bucket with versioning, AES-256 encryption, and public access blocked
- DynamoDB table (`PAY_PER_REQUEST`) for state locking

Update `env/dev/backend.tf` if you used custom names.

---

## Step 4 — Validate Terraform (optional)

Quick lint and validation without deploying anything:

```bash
./scripts/validate.sh
```

Checks:
1. `terraform fmt` formatting
2. HCL syntax for every module
3. `env/dev` validation (if initialized)
4. Required files (`variables.tf`, `outputs.tf`) in each module

---

## Step 5 — Deploy to AWS

### Option A — One Command (recommended)

```bash
# Set up variables
cp env/dev/terraform.tfvars.example env/dev/terraform.tfvars
# Edit terraform.tfvars with your aws_profile, region, db_name, db_user

# Export secrets
export TF_VAR_db_password="YourSecureP@ssw0rd"
export TF_VAR_app_key="base64:YOUR_LARAVEL_APP_KEY"

# Deploy everything: Terraform apply → Docker build → ECR push → ECS redeploy
./scripts/deploy.sh dev latest
```

### Option B — Step by Step

#### 5b.1 — Terraform

```bash
cp env/dev/terraform.tfvars.example env/dev/terraform.tfvars
# Edit terraform.tfvars — use a placeholder image_url for now

export TF_VAR_db_password="YourSecureP@ssw0rd"
export TF_VAR_app_key="base64:YOUR_LARAVEL_APP_KEY"

cd env/dev
terraform init
terraform plan        # Review — expect ~30+ resources on first run
terraform apply
```

Note these outputs:
- `alb_dns_name` — your app's URL
- `ecr_repository_url` — where to push Docker images

#### 5b.2 — Push Docker Image

```bash
cd ../..

# Use the helper script
./scripts/push-ecr.sh latest
```

Or manually:

```bash
ECR_URL=$(cd env/dev && terraform output -raw ecr_repository_url)
REGION="ap-south-1"

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $(echo $ECR_URL | cut -d/ -f1)

docker build -t $ECR_URL:latest laravel-app/
docker push $ECR_URL:latest
```

#### 5b.3 — Update ECS with the Real Image

```bash
cd env/dev
terraform apply -var="image_url=${ECR_URL}:latest"
```

#### 5b.4 — Force Redeploy (if image tag unchanged)

```bash
aws ecs update-service \
  --cluster laravel-dev \
  --service laravel-dev-service \
  --force-new-deployment \
  --region ap-south-1
```

---

## Step 6 — Verify

Wait 2–3 minutes for ECS tasks to register with the ALB, then:

```bash
ALB_DNS=$(cd env/dev && terraform output -raw alb_dns_name)

# Health check
curl -I http://${ALB_DNS}/up
# → HTTP/1.1 200 OK

# Home page
curl http://${ALB_DNS}/
# → Laravel welcome page HTML
```

---

## Step 7 — Monitor

### Tail ECS Logs

```bash
aws logs tail /ecs/laravel-dev --follow --region ap-south-1
```

### ECS Service Status

```bash
aws ecs describe-services \
  --cluster laravel-dev \
  --services laravel-dev-service \
  --region ap-south-1 \
  --query 'services[0].{
    Status: status,
    Running: runningCount,
    Desired: desiredCount,
    Deployments: deployments[*].{
      Status: status,
      Running: runningCount,
      Desired: desiredCount
    }
  }'
```

### CloudWatch Alarms

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix laravel-dev \
  --region ap-south-1 \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' \
  --output table
```

### RDS Connection (from ECS task)

```bash
# Get RDS endpoint
cd env/dev && terraform output rds_endpoint
```

---

## Step 8 — Tear Down

### Destroy Infrastructure

```bash
# Using the script (prompts for confirmation on staging/prod)
./scripts/destroy.sh dev

# Or manually
cd env/dev
terraform destroy
```

### Remove State Backend (optional)

```bash
aws s3 rb s3://your-terraform-state-bucket --force
aws dynamodb delete-table --table-name terraform-lock --region ap-south-1
```

---

## What Happens During Deployment

```
deploy.sh
  │
  ├─ 1. push-ecr.sh
  │     ├── AWS ECR login
  │     ├── docker build (laravel-app/Dockerfile)
  │     │     ├── Stage: base     → PHP 8.3 + Nginx + Supervisor + extensions
  │     │     ├── Stage: deps     → composer install (cached layer)
  │     │     └── Stage: production → copy app + optimize autoloader
  │     └── docker push → ECR
  │
  ├─ 2. terraform apply
  │     ├── VPC (2-AZ, public/private subnets, NAT Gateway)
  │     ├── Security Groups (ALB → App → RDS)
  │     ├── ALB (public subnets, health check on /up)
  │     ├── ECR repository
  │     ├── IAM roles (execution + task)
  │     ├── RDS MySQL 8.0 (private subnets, encrypted)
  │     ├── Secrets Manager (DB credentials)
  │     ├── ECS Fargate (task definition + service + autoscaling)
  │     └── CloudWatch alarms
  │
  └─ 3. ECS force redeploy
        └── Container starts → entrypoint.sh:
              ├── php artisan config:cache
              ├── php artisan route:cache
              ├── php artisan view:cache
              ├── php artisan migrate --force (if RUN_MIGRATIONS=true)
              └── supervisord (php-fpm + nginx)
```

---

## Module-Specific Terraform Commands

All commands run from `env/dev/` after `terraform init`. Use `-target` to plan/apply
individual modules instead of the full stack.

```bash
cd env/dev
```

### Module Dependency Order

Modules must be applied in dependency order. The diagram below shows what each module needs:

```
  vpc ─────────┬──→ sg ──────────┬──→ alb ──────┐
               │                 ├──→ rds ───┐   │
               │                 │           │   │
  ecr          │   secrets ──→ iam           │   │
               │                 │           │   │
               └─────────────────┴───────────┴───┴──→ ecs ──→ monitoring
```

**Independent (no module dependencies):** `vpc`, `ecr`, `secrets`
**Depends on VPC + SG:** `alb`, `rds`
**Depends on secrets:** `iam`
**Depends on almost everything:** `ecs`
**Depends on ECS + RDS:** `monitoring`

### Plan / Apply a Single Module

```bash
# Syntax
terraform plan  -target=module.<name>
terraform apply -target=module.<name>
```

### Layer-by-Layer Commands

**Layer 1 — Foundations (no dependencies, can run in any order):**

```bash
terraform apply -target=module.vpc
terraform apply -target=module.ecr
terraform apply -target=module.secrets
```

**Layer 2 — Networking & Data (depends on Layer 1):**

```bash
terraform apply -target=module.sg          # needs: vpc
terraform apply -target=module.iam         # needs: secrets
```

**Layer 3 — Services (depends on Layer 1 + 2):**

```bash
terraform apply -target=module.alb         # needs: vpc, sg
terraform apply -target=module.rds         # needs: vpc, sg
```

**Layer 4 — Application (depends on everything above):**

```bash
terraform apply -target=module.ecs         # needs: vpc, sg, iam, alb, rds, secrets
```

**Layer 5 — Observability:**

```bash
terraform apply -target=module.monitoring  # needs: ecs, rds
```

### Common Scenarios

**Rebuild only ECS (e.g. new image, changed env vars):**

```bash
terraform apply -target=module.ecs
```

**Update RDS settings (instance class, storage, backups):**

```bash
terraform plan  -target=module.rds
terraform apply -target=module.rds
```

**Recreate ALB (health check path, listener rules):**

```bash
terraform apply -target=module.alb
# ECS service references the target group, so also refresh:
terraform apply -target=module.ecs
```

**Update IAM policies:**

```bash
terraform apply -target=module.iam
# ECS tasks use these roles, force a redeploy:
terraform apply -target=module.ecs
```

**Rotate DB credentials in Secrets Manager:**

```bash
terraform apply -target=module.secrets
# ECS pulls secrets at task launch, so force a redeploy:
terraform apply -target=module.ecs
```

**Update monitoring thresholds:**

```bash
terraform apply -target=module.monitoring
```

**Apply multiple modules at once:**

```bash
terraform apply \
  -target=module.vpc \
  -target=module.sg \
  -target=module.alb
```

### Destroy a Single Module

```bash
terraform destroy -target=module.monitoring
terraform destroy -target=module.ecs
# Destroy in reverse dependency order to avoid orphaned references
```

**Full reverse-order teardown (manual):**

```bash
terraform destroy -target=module.monitoring
terraform destroy -target=module.ecs
terraform destroy -target=module.rds
terraform destroy -target=module.alb
terraform destroy -target=module.iam
terraform destroy -target=module.secrets
terraform destroy -target=module.sg
terraform destroy -target=module.ecr
terraform destroy -target=module.vpc
```

> **Tip:** `terraform destroy` (without `-target`) handles dependency ordering
> automatically. Use per-module destroy only when you need to remove specific
> resources while keeping the rest running.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| ECS tasks keep restarting | Container can't reach ECR or crashes on boot | Check NAT Gateway exists; check ECS logs for errors |
| ALB health check failing | `/up` returns non-200 | Verify `APP_KEY` is set; check ECS logs for config errors |
| RDS connection refused | Security group or subnet mismatch | Verify App SG allows outbound 3306 to RDS SG |
| `terraform plan` shows 0 changes but app won't start | Old Docker image cached | Force redeploy: `./scripts/deploy.sh dev latest` |
| `docker build` fails on composer | Missing `composer.lock` | Run `cd laravel-app && composer install` first |
| Container starts but pages 502 | Nginx/PHP-FPM not ready yet | Wait 1–2 min; check supervisor + nginx logs in container |
| Migrations fail on startup | RDS not ready or wrong credentials | Check `DB_HOST`, `DB_SECRET_ARN`; verify Secrets Manager values |
| `terraform init` fails on backend | S3 bucket or DynamoDB table missing | Run `./scripts/bootstrap-state.sh` first |

### Quick Debug Commands

```bash
# Check ECS task status
aws ecs list-tasks --cluster laravel-dev --region ap-south-1

# Describe a failing task (get task ARN from above)
aws ecs describe-tasks \
  --cluster laravel-dev \
  --tasks <TASK_ARN> \
  --region ap-south-1 \
  --query 'tasks[0].{Status:lastStatus,StopReason:stoppedReason,Containers:containers[*].{Name:name,Status:lastStatus,Reason:reason}}'

# Check if ALB target group has healthy targets
aws elbv2 describe-target-health \
  --target-group-arn $(cd env/dev && terraform output -raw target_group_arn 2>/dev/null || echo "check-manually") \
  --region ap-south-1
```
