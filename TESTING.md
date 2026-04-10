# Testing Guide — Laravel 13 on AWS ECS

End-to-end testing of this Terraform infrastructure with a sample Laravel 13
application. There are two testing paths:

1. **Local** — Docker Compose on your machine (no AWS needed)
2. **AWS** — Full deployment to ECS Fargate

---

## Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| PHP | >= 8.3 | `php -v` |
| Composer | >= 2 | `composer -V` |
| Docker | >= 24 | `docker --version` |
| Docker Compose | >= 2 | `docker compose version` |
| Terraform | ~> 1.5 | `terraform -version` |
| AWS CLI | >= 2 | `aws --version` |

---

## Step 1 — Create a Sample Laravel 13 App

Scaffold a fresh Laravel 13 project **inside this repo**:

```bash
cd /var/www/html/terraform-aws-laravel-infra

# Install Laravel 13 into the current directory
# (--force because the directory is not empty)
composer create-project laravel/laravel laravel-app
cp -rn laravel-app/* laravel-app/.* . 2>/dev/null || true
rm -rf laravel-app

# Generate an app key
php artisan key:generate
```

The Laravel health-check endpoint `/up` is built-in since Laravel 11 and works
out of the box — our ALB health check points to it.

---

## Step 2 — Test Locally with Docker Compose

This validates the Dockerfile, Nginx config, and PHP setup before touching AWS.

```bash
# Build and start the stack
docker compose up --build -d

# Wait for MySQL to be healthy, then run migrations
docker compose exec app php artisan migrate --force

# Test the health endpoint
curl http://localhost:8080/up
# Should return 200 OK

# Test the home page
curl -I http://localhost:8080/
# Should return 200

# View logs
docker compose logs -f app

# Tear down when done
docker compose down -v
```

**If this works**, the Docker image is production-ready and you can proceed to
AWS deployment.

---

## Step 3 — Configure AWS Credentials

```bash
aws configure
# Or export directly:
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="ap-south-1"

# Verify
aws sts get-caller-identity
```

Your IAM user/role needs permissions for: VPC, EC2, ECS, ECR, RDS, ALB,
CloudWatch, Secrets Manager, IAM, S3, DynamoDB.

---

## Step 4 — Bootstrap Terraform State Backend

The S3 bucket and DynamoDB table must exist before `terraform init`:

```bash
# Uses defaults: bucket=my-terraform-state-bucket, region=ap-south-1, table=terraform-lock
./scripts/bootstrap-state.sh

# Or with custom names:
./scripts/bootstrap-state.sh my-company-tf-state ap-south-1 terraform-lock
```

Then update `env/dev/backend.tf` if you used custom names.

---

## Step 5 — Run Terraform Validation

Quick validation without deploying anything:

```bash
./scripts/validate.sh
```

This checks formatting, module validity, and file structure.

---

## Step 6a — Deploy (Step by Step)

### 6a.1 — Terraform Plan

```bash
cd env/dev

# Create your tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set a placeholder image_url for now

# Supply the DB password
export TF_VAR_db_password="YourSecureP@ssw0rd"

terraform init
terraform plan
```

Review the plan carefully. For a fresh deployment you should see ~30+ resources.

### 6a.2 — Terraform Apply

```bash
terraform apply
```

Note the outputs:
- `alb_dns_name` — your application URL
- `ecr_repository_url` — where to push Docker images

### 6a.3 — Build and Push Docker Image

```bash
# Back to repo root
cd ../..

# Get the ECR URL from Terraform output
ECR_URL=$(cd env/dev && terraform output -raw ecr_repository_url)
REGION="ap-south-1"

# Login to ECR
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR_URL

# Build
docker build -t $ECR_URL:latest .

# Push
docker push $ECR_URL:latest
```

### 6a.4 — Update ECS with the Real Image

```bash
cd env/dev

terraform apply -var="image_url=${ECR_URL}:latest"
```

### 6a.5 — Verify

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)

# Wait 2-3 minutes for ECS tasks to start, then:
curl -I http://${ALB_DNS}/up
# Should return HTTP 200

curl http://${ALB_DNS}/
# Should return the Laravel welcome page
```

---

## Step 6b — Deploy (One Command)

If you prefer a single script:

```bash
export TF_VAR_db_password="YourSecureP@ssw0rd"

# Deploy everything (Terraform + Docker build + ECR push + ECS redeploy)
./scripts/deploy.sh latest
```

---

## Step 7 — Monitor

### CloudWatch Logs

```bash
aws logs tail /ecs/laravel-dev --follow --region ap-south-1
```

### ECS Service Status

```bash
aws ecs describe-services \
  --cluster laravel-dev \
  --services laravel-dev-service \
  --region ap-south-1 \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Deployments:deployments[*].{Status:status,Running:runningCount,Desired:desiredCount}}'
```

### CloudWatch Alarms

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix laravel-dev \
  --region ap-south-1 \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}'
```

---

## Step 8 — Tear Down

```bash
cd env/dev
terraform destroy

# Optionally remove the state backend
aws s3 rb s3://my-terraform-state-bucket --force
aws dynamodb delete-table --table-name terraform-lock --region ap-south-1
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| ECS tasks keep restarting | Image can't reach ECR | Verify NAT Gateway exists, check SG egress |
| ALB health check failing | `/up` returns non-200 | Check `APP_KEY` is set, run `php artisan config:cache` |
| RDS connection refused | SG or subnet mismatch | Verify App SG → RDS SG rule, subnets in same VPC |
| Terraform plan shows 0 changes but app won't start | Old image cached | Run `./scripts/deploy.sh` or force ECS redeployment |
| `docker build` fails on composer | Missing `composer.lock` | Run `composer install` locally first to generate it |
