#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ERRORS=0

echo "============================================"
echo "  Terraform Validation Suite"
echo "============================================"
echo ""

# ── 1. Format check ─────────────────────────────
echo "==> [1/4] Checking formatting..."
if terraform fmt -check -recursive "${PROJECT_ROOT}" >/dev/null 2>&1; then
  echo "    PASS"
else
  echo "    FAIL — run: terraform fmt -recursive ."
  terraform fmt -check -recursive "${PROJECT_ROOT}" 2>&1 | sed 's/^/          /'
  ERRORS=$((ERRORS + 1))
fi

# ── 2. Validate modules (HCL syntax only) ───────
echo "==> [2/4] Checking module HCL syntax..."
for mod_dir in "${PROJECT_ROOT}"/modules/*/; do
  mod_name=$(basename "${mod_dir}")

  tmpdir=$(mktemp -d)
  trap "rm -rf ${tmpdir}" EXIT

  # Create a thin wrapper that declares the AWS provider so the module can be validated standalone
  cat > "${tmpdir}/validate.tf" <<EOF
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

module "under_test" {
  source = "${mod_dir}"
EOF

  # Auto-fill every variable with null so validate doesn't complain about missing values
  if [ -f "${mod_dir}/variables.tf" ]; then
    grep -oP 'variable\s+"\K[^"]+' "${mod_dir}/variables.tf" | while read -r varname; do
      echo "  ${varname} = null" >> "${tmpdir}/validate.tf"
    done
  fi

  echo "}" >> "${tmpdir}/validate.tf"

  if terraform -chdir="${tmpdir}" init -backend=false >/dev/null 2>&1 \
     && terraform -chdir="${tmpdir}" validate >/dev/null 2>&1; then
    echo "    PASS  modules/${mod_name}"
  else
    echo "    FAIL  modules/${mod_name}"
    terraform -chdir="${tmpdir}" validate 2>&1 | sed 's/^/          /'
    ERRORS=$((ERRORS + 1))
  fi

  rm -rf "${tmpdir}"
  trap - EXIT
done

# ── 3. Validate environment ─────────────────────
echo "==> [3/4] Validating env/dev..."
ENV_DIR="${PROJECT_ROOT}/env/dev"

if [ -d "${ENV_DIR}/.terraform" ]; then
  if terraform -chdir="${ENV_DIR}" validate 2>&1 | sed 's/^/    /'; then
    :
  else
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "    SKIP — run 'cd env/dev && terraform init' first"
fi

# ── 4. Check required files ─────────────────────
echo "==> [4/4] Checking module file structure..."
for mod_dir in "${PROJECT_ROOT}"/modules/*/; do
  mod_name=$(basename "${mod_dir}")
  missing=""
  [ ! -f "${mod_dir}/variables.tf" ] && missing="${missing} variables.tf"
  [ ! -f "${mod_dir}/outputs.tf" ]   && missing="${missing} outputs.tf"

  if [ -z "${missing}" ]; then
    echo "    PASS  modules/${mod_name}"
  else
    echo "    WARN  modules/${mod_name} — missing:${missing}"
  fi
done

echo ""
echo "============================================"
if [ ${ERRORS} -eq 0 ]; then
  echo "  All checks passed!"
else
  echo "  ${ERRORS} check(s) failed."
  exit 1
fi
