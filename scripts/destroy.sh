#!/usr/bin/env bash
set -euo pipefail

#
# Destroy all Terraform-managed resources for a given environment.
# Usage:  ./scripts/destroy.sh [ENVIRONMENT]
# Env:    AWS_PROFILE  (default: shailesh-aws)
#
# Examples:
#   ./scripts/destroy.sh          # destroys dev (default)
#   ./scripts/destroy.sh dev
#   ./scripts/destroy.sh staging
#   ./scripts/destroy.sh prod
#

ENVIRONMENT="${1:-dev}"
export AWS_PROFILE="${AWS_PROFILE:-shailesh-aws}"

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

echo "============================================"
echo "  TERRAFORM DESTROY"
echo "  Environment : ${ENVIRONMENT}"
echo "  AWS Profile : ${AWS_PROFILE}"
echo "  Directory   : ${ENV_DIR}"
echo "============================================"
echo ""

# ── Safety confirmation for protected environments ──
if [[ "${ENVIRONMENT}" == "prod" || "${ENVIRONMENT}" == "staging" ]]; then
  echo "WARNING: You are about to destroy the '${ENVIRONMENT}' environment!"
  echo ""
  read -rp "Type the environment name to confirm: " CONFIRM
  if [ "${CONFIRM}" != "${ENVIRONMENT}" ]; then
    echo "Confirmation did not match. Aborting."
    exit 1
  fi
  echo ""
fi

cd "${ENV_DIR}"

# ── 1. Terraform init ────────────────────────────
echo "==> Initializing Terraform..."
terraform init -input=false
echo ""

# ── 2. Terraform destroy ─────────────────────────
echo "==> Destroying all resources for '${ENVIRONMENT}'..."
terraform destroy -auto-approve -input=false
echo ""

echo "============================================"
echo "  All '${ENVIRONMENT}' resources destroyed."
echo "============================================"
