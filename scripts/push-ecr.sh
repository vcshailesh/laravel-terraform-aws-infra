#!/usr/bin/env bash
set -euo pipefail

#
# Build the laravel-app Docker image and push it to AWS ECR.
# Usage:  ./scripts/push-ecr.sh [IMAGE_TAG]
# Env:    AWS_PROFILE  (default: shailesh-aws)
#         AWS_REGION   (default: ap-south-1)
#         ECR_REPOSITORY (default: laravel-app)
#

export AWS_PROFILE="${AWS_PROFILE:-shailesh-aws}"
REGION="${AWS_REGION:-ap-south-1}"
REPO_NAME="${ECR_REPOSITORY:-laravel-app}"
IMAGE_TAG="${1:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

# ── 1. Resolve AWS account & registry ─────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
FULL_TAG="${REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"

echo "==> AWS Profile:  ${AWS_PROFILE}"
echo "==> AWS Account:  ${ACCOUNT_ID}"
echo "==> Registry:     ${REGISTRY}"
echo "==> Repository:   ${REPO_NAME}"
echo "==> Image tag:    ${IMAGE_TAG}"
echo "==> Full image:   ${FULL_TAG}"
echo ""

# ── 2. Ensure ECR repository exists ──────────────
if ! aws ecr describe-repositories \
      --repository-names "${REPO_NAME}" \
      --region "${REGION}" >/dev/null 2>&1; then
  echo "==> ECR repository '${REPO_NAME}' not found. Creating..."
  aws ecr create-repository \
    --repository-name "${REPO_NAME}" \
    --region "${REGION}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --query 'repository.repositoryUri' \
    --output text
  echo ""
fi

# ── 3. Docker login to ECR ───────────────────────
echo "==> Logging in to ECR..."
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${REGISTRY}"
echo ""

# ── 4. Build the image ───────────────────────────
echo "==> Building image: ${FULL_TAG}"
docker build -t "${FULL_TAG}" laravel-app/
echo ""

# ── 5. Push the image ────────────────────────────
echo "==> Pushing image: ${FULL_TAG}"
docker push "${FULL_TAG}"

if [ "${IMAGE_TAG}" != "latest" ]; then
  echo "==> Also tagging as latest..."
  docker tag "${FULL_TAG}" "${REGISTRY}/${REPO_NAME}:latest"
  docker push "${REGISTRY}/${REPO_NAME}:latest"
fi

echo ""
echo "==> Done! Image pushed to ECR:"
echo "    ${FULL_TAG}"
