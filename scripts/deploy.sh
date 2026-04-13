#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-shailesh-aws}"
export AWS_REGION="${AWS_REGION:-ap-south-1}"
export ECR_REPOSITORY="${ECR_REPOSITORY:-laravel-app}"
IMAGE_TAG="${1:-latest}"
ENV_DIR="env/dev"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

echo "==> Using AWS profile: ${AWS_PROFILE}"

# ── 1. Get AWS account ID ────────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URL="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

echo "==> AWS Account: ${ACCOUNT_ID}"
echo "==> Registry:    ${REGISTRY}"
echo "==> Repository:  ${ECR_REPOSITORY}"
echo "==> Image tag:   ${IMAGE_TAG}"
echo "==> Image URL:   ${IMAGE_URL}"
echo ""

# ── 2. Build and push Docker image to ECR ────────
echo "==> Building and pushing Docker image to ECR..."
"${SCRIPT_DIR}/push-ecr.sh" "${IMAGE_TAG}"

# ── 3. Terraform init + apply (creates all resources) ──
echo ""
echo "==> Running Terraform..."

cd "${ENV_DIR}"

terraform init -input=false

terraform apply -input=false -auto-approve \
  -var="image_url=${IMAGE_URL}"

cd "${PROJECT_ROOT}"

# ── 4. Force ECS redeployment ────────────────────
echo ""
echo "==> Triggering ECS redeployment..."
aws ecs update-service \
  --cluster laravel-dev \
  --service laravel-dev-service \
  --force-new-deployment \
  --region "${AWS_REGION}" \
  --query 'service.serviceName' \
  --output text

echo ""
echo "==> Deployment triggered! Monitor with:"
echo "    aws ecs describe-services --cluster laravel-dev --services laravel-dev-service --region ${AWS_REGION} --query 'services[0].deployments'"
