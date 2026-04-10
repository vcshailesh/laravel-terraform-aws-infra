#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-shailesh-aws}"
REGION="${AWS_REGION:-ap-south-1}"
REPO_NAME="${ECR_REPOSITORY:-laravel-app}"
IMAGE_TAG="${1:-latest}"
ENV_DIR="env/dev"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

echo "==> Using AWS profile: ${AWS_PROFILE}"

# ── 1. Get AWS account ID ────────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "==> AWS Account: ${ACCOUNT_ID}"
echo "==> Registry:    ${REGISTRY}"
echo "==> Repository:  ${REPO_NAME}"
echo "==> Image tag:   ${IMAGE_TAG}"
echo ""

# ── 2. Terraform init + apply (creates ECR, ECS, etc.) ──
echo "==> Running Terraform..."

cd "${ENV_DIR}"

terraform init -input=false

terraform apply -input=false -auto-approve \
  -var="image_url=${REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"

cd "${PROJECT_ROOT}"

# ── 3. Docker login to ECR ───────────────────────
echo ""
echo "==> Logging in to ECR..."
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${REGISTRY}"

# ── 4. Build and push ────────────────────────────
FULL_TAG="${REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"

echo ""
echo "==> Building image: ${FULL_TAG}"
docker build -t "${FULL_TAG}" .

echo ""
echo "==> Pushing image..."
docker push "${FULL_TAG}"

# Also tag as latest if not already
if [ "${IMAGE_TAG}" != "latest" ]; then
  docker tag "${FULL_TAG}" "${REGISTRY}/${REPO_NAME}:latest"
  docker push "${REGISTRY}/${REPO_NAME}:latest"
fi

# ── 5. Force ECS redeployment ────────────────────
echo ""
echo "==> Triggering ECS redeployment..."
aws ecs update-service \
  --cluster laravel-dev \
  --service laravel-dev-service \
  --force-new-deployment \
  --region "${REGION}" \
  --query 'service.serviceName' \
  --output text

echo ""
echo "==> Deployment triggered! Monitor with:"
echo "    aws ecs describe-services --cluster laravel-dev --services laravel-dev-service --region ${REGION} --query 'services[0].deployments'"
