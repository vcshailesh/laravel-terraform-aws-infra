#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-shailesh-aws}"
BUCKET_NAME="${1:-my-terraform-state-bucket}"
REGION="${2:-ap-south-1}"
TABLE_NAME="${3:-terraform-lock}"

export AWS_PROFILE

echo "==> Using AWS profile: ${AWS_PROFILE}"
echo "==> Creating S3 bucket: ${BUCKET_NAME} in ${REGION}"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "    Bucket already exists, skipping."
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

  aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

  echo "    Bucket created with versioning, encryption, and public access blocked."
fi

echo "==> Creating DynamoDB table: ${TABLE_NAME} in ${REGION}"

if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "    Table already exists, skipping."
else
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo "    Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
  echo "    Table created."
fi

echo ""
echo "==> Done! Update env/dev/backend.tf with:"
echo ""
echo "    bucket         = \"${BUCKET_NAME}\""
echo "    dynamodb_table = \"${TABLE_NAME}\""
echo "    region         = \"${REGION}\""
