#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-/app}"
DB_PATH="${CPG_DB_PATH:-${PROJECT_ROOT}/data/cpg.db}"

if [[ -f "${DB_PATH}" ]]; then
  echo "CPG DB already exists: ${DB_PATH}"
  exit 0
fi

echo "CPG DB not found, generating..."
"${PROJECT_ROOT}/tools/generate_cpg_db.sh"
