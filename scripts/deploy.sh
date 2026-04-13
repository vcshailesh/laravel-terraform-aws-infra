#!/usr/bin/env bash
set -euo pipefail

#
# Deploy infrastructure and application for a given environment.
# Usage:  ./scripts/deploy.sh [ENVIRONMENT] [IMAGE_TAG]
# Env:    AWS_PROFILE    (default: shailesh-aws)
#         AWS_REGION     (default: ap-south-1)
#         ECR_REPOSITORY (default: laravel-app)
#
# Examples:
#   ./scripts/deploy.sh                  # deploy dev with latest tag
#   ./scripts/deploy.sh dev v1.2.0
#   ./scripts/deploy.sh staging latest
#   ./scripts/deploy.sh prod abc123
#

ENVIRONMENT="${1:-dev}"
IMAGE_TAG="${2:-latest}"
PROJECT="laravel"

export AWS_PROFILE="${AWS_PROFILE:-shailesh-aws}"
export AWS_REGION="${AWS_REGION:-ap-south-1}"
export ECR_REPOSITORY="${ECR_REPOSITORY:-laravel-app}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${PROJECT_ROOT}/env/${ENVIRONMENT}"

# ── Validate environment directory exists ─────────
if [ ! -d "${ENV_DIR}" ]; then
  echo "Error: Environment directory '${ENV_DIR}' does not exist."
  echo "Available environments:"
  ls -1 "${PROJECT_ROOT}/env/"
  exit 1
fi

CLUSTER_NAME="${PROJECT}-${ENVIRONMENT}"
SERVICE_NAME="${PROJECT}-${ENVIRONMENT}-service"

cd "${PROJECT_ROOT}"

# ── 1. Get AWS account ID ────────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URL="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

echo "============================================"
echo "  DEPLOY"
echo "  Environment : ${ENVIRONMENT}"
echo "  AWS Profile : ${AWS_PROFILE}"
echo "  AWS Account : ${ACCOUNT_ID}"
echo "  Registry    : ${REGISTRY}"
echo "  Repository  : ${ECR_REPOSITORY}"
echo "  Image tag   : ${IMAGE_TAG}"
echo "  Image URL   : ${IMAGE_URL}"
echo "  ECS Cluster : ${CLUSTER_NAME}"
echo "  ECS Service : ${SERVICE_NAME}"
echo "============================================"
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
  --cluster "${CLUSTER_NAME}" \
  --service "${SERVICE_NAME}" \
  --force-new-deployment \
  --region "${AWS_REGION}" \
  --query 'service.serviceName' \
  --output text

echo ""
echo "==> Deployment triggered! Monitor with:"
echo "    aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION} --query 'services[0].deployments'"
