# AGENTS.md — Terraform AWS Laravel Infrastructure

## Project Overview

Production-grade AWS infrastructure for a Laravel application using ECS Fargate,
managed with Terraform. Every module is reusable and environment-agnostic; concrete
values live in `env/<environment>/`.

## Directory Layout

```
.
├── AGENTS.md                 # This file — AI agent guidance
├── env/
│   ├── dev/                  # Development environment root module
│   ├── staging/              # (future) Staging environment
│   └── prod/                 # (future) Production environment
├── modules/
│   ├── alb/                  # Application Load Balancer
│   ├── ecr/                  # Elastic Container Registry
│   ├── ecs/                  # ECS Fargate cluster, service, task
│   ├── iam/                  # IAM roles for ECS
│   ├── monitoring/           # CloudWatch alarms & dashboards
│   ├── rds/                  # RDS MySQL
│   ├── secrets/              # Secrets Manager
│   ├── security-group/       # Security groups
│   └── vpc/                  # VPC, subnets, NAT, IGW
├── global/                   # Cross-environment resources (Route53, ACM, etc.)
├── scripts/                  # Helper scripts (plan, apply, bootstrap)
└── .github/workflows/        # CI/CD pipelines
```

## Coding Standards

### Terraform Version & Providers

- Pin `required_version` to `~> 1.5` (or the minor range you use).
- Pin every provider in `required_providers` with a pessimistic constraint (`~> 6.0`).
- **Commit `.terraform.lock.hcl`** so CI reproducibly installs the same provider builds.

### File Conventions per Module

| File | Purpose |
|------|---------|
| `main.tf` | Primary resources |
| `variables.tf` | All input variables (with `description`, `type`, and optional `default`) |
| `outputs.tf` | All outputs (with `description`) |
| `versions.tf` | `terraform { required_version, required_providers }` (root modules only) |
| `locals.tf` | Computed values and common tag maps |
| `data.tf` | Data sources |

Never mix variable declarations into resource files.

### Naming

- **Resources**: `aws_<service>_<resource>` with a logical name like `this`, `main`, or a descriptive noun. Avoid numbering (`db1`, `db2`).
- **Variables**: `snake_case`, descriptive. Prefix booleans with `enable_` or `is_`.
- **Outputs**: Match the attribute being exposed (`vpc_id`, `alb_dns_name`).
- **Resource names in AWS**: `<project>-<environment>-<component>` (e.g., `laravel-dev-alb`).

### Tagging Strategy

Every taggable resource MUST carry these tags:

```hcl
tags = {
  Project     = var.project
  Environment = var.environment
  ManagedBy   = "terraform"
}
```

Use a `locals` block for the common map and merge resource-specific tags:

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags       = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpc" })
}
```

### Variables

- **Always** declare `type` and `description`.
- Sensitive values (`password`, `secret_key`) must set `sensitive = true`.
- Use `validation` blocks for values with known constraints (CIDR ranges, port numbers, etc.).
- Provide sensible `default` values for non-secret, non-environment-specific variables.

### Security Requirements

1. **Encryption at rest** on every data store (RDS `storage_encrypted = true`, EBS, S3 `sse`).
2. **Encryption in transit** — HTTPS listeners on ALB; TLS for RDS connections.
3. **No public access** to databases — RDS must be `publicly_accessible = false`.
4. **Least-privilege IAM** — use specific policy ARNs; avoid `*` actions/resources.
5. **Secrets via Secrets Manager or SSM** — never hardcode credentials in Terraform.
6. **Deletion protection** on stateful resources (RDS, ALB) in staging/production.
7. **VPC Flow Logs** enabled for audit and troubleshooting.

### Networking

- Public subnets → ALB only.
- Private subnets → ECS tasks, RDS. Outbound via NAT Gateway.
- Each AZ gets one public and one private subnet (minimum 2 AZs).
- NAT Gateway is required for Fargate tasks in private subnets to pull ECR images.

### RDS Best Practices

- `multi_az = true` in staging/production.
- `backup_retention_period >= 7`.
- `storage_encrypted = true` always.
- `deletion_protection = true` in staging/production.
- `skip_final_snapshot = false` in production (provide `final_snapshot_identifier`).
- Enable Performance Insights for prod.

### ECS Best Practices

- Enable Container Insights on the cluster.
- Use deployment circuit breaker with rollback.
- Configure Application Auto Scaling (target tracking on CPU/memory).
- Keep `desired_count >= 2` in production for HA across AZs.
- Pass environment name through `APP_ENV` container environment variable.

### Monitoring

- Every alarm MUST have `alarm_actions` pointing to an SNS topic.
- Minimum alarms: ECS CPU high, ECS memory high, ALB 5xx count, RDS CPU, RDS free storage.
- CloudWatch log retention ≥ 14 days in production (7 days acceptable for dev).

### CI/CD

- PR workflow: `init` → `validate` → `fmt -check` → `plan` (posted as PR comment).
- Merge-to-main workflow: `init` → `plan` → `apply -auto-approve`.
- Use OIDC for AWS authentication in GitHub Actions — avoid long-lived IAM keys.
- Pin all GitHub Action versions to full SHA, not just major tag.

## Environment Patterns

Each `env/<name>/` is an independent root module:

```
env/dev/
  ├── versions.tf          # terraform + required_providers
  ├── backend.tf           # S3 remote state
  ├── providers.tf         # provider "aws" { ... }
  ├── main.tf              # module calls
  ├── variables.tf         # input variables
  ├── outputs.tf           # stack outputs
  ├── locals.tf            # common tags, computed values
  ├── terraform.tfvars.example
  └── terraform.tfvars     # git-ignored
```

## Module Interface Contract

Every module MUST:

1. Accept `project` and `environment` variables for naming and tagging.
2. Declare all inputs in `variables.tf` with `type` + `description`.
3. Export relevant IDs/ARNs in `outputs.tf` with `description`.
4. Tag every taggable resource.
5. Not hardcode region, AZs, or account-specific values.
