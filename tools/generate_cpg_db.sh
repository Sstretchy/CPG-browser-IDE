#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_DIR="${REPOS_DIR:-${PROJECT_ROOT}/repos}"
DATA_DIR="${DATA_DIR:-${PROJECT_ROOT}/data}"
OUT_DB="${OUT_DB:-${DATA_DIR}/cpg.db}"

PROMETHEUS_REPO="${PROMETHEUS_REPO:-https://github.com/prometheus/prometheus.git}"
CLIENT_GOLANG_REPO="${CLIENT_GOLANG_REPO:-https://github.com/prometheus/client_golang.git}"
ADAPTER_REPO="${ADAPTER_REPO:-https://github.com/kubernetes-sigs/prometheus-adapter.git}"
NODE_EXPORTER_REPO="${NODE_EXPORTER_REPO:-https://github.com/prometheus/node_exporter.git}"

PROMETHEUS_REF="${PROMETHEUS_REF:-8937cbd3955513efe0e0c76c58a3e0665a35df3a}"
CLIENT_GOLANG_REF="${CLIENT_GOLANG_REF:-bf37be4fecc0a3d89f980252e206b67806990e56}"
ADAPTER_REF="${ADAPTER_REF:-01919d0ef11859bc214e0c8a8bd5368afd9d47f7}"
NODE_EXPORTER_REF="${NODE_EXPORTER_REF:-master}"
GO_BIN="${GO_BIN:-/usr/local/go/bin/go}"
export PATH="/usr/local/go/bin:/usr/bin:${PATH}"

# Memory/parallelism guardrails for heavy first run (can be overridden via env).
CPG_GOMAXPROCS="${CPG_GOMAXPROCS:-1}"
CPG_GOGC="${CPG_GOGC:-20}"
CPG_GOMEMLIMIT="${CPG_GOMEMLIMIT:-4GiB}"
export GOMAXPROCS="${GOMAXPROCS:-${CPG_GOMAXPROCS}}"
export GOGC="${GOGC:-${CPG_GOGC}}"
export GOMEMLIMIT="${GOMEMLIMIT:-${CPG_GOMEMLIMIT}}"
export GOFLAGS="${GOFLAGS:--p=1}"

clone_or_update() {
  local repo_url="$1"
  local repo_dir="$2"
  local repo_ref="$3"

  if [[ ! -d "${repo_dir}/.git" ]]; then
    git clone --depth 1 "${repo_url}" "${repo_dir}"
  fi

  (
    cd "${repo_dir}"
    git fetch --depth 1 origin "${repo_ref}"
    git checkout -q FETCH_HEAD
  )
}

build_generator() {
  if [[ ! -x "${GO_BIN}" ]]; then
    echo "error: go binary not found at ${GO_BIN}" >&2
    exit 1
  fi

  "${GO_BIN}" version
  echo "Using limits: GOMAXPROCS=${GOMAXPROCS} GOGC=${GOGC} GOMEMLIMIT=${GOMEMLIMIT} GOFLAGS=${GOFLAGS}"

  (
    cd "${PROJECT_ROOT}/cpg-gen-src"
    "${GO_BIN}" build -o "${PROJECT_ROOT}/cpg-gen" .
  )
}

mkdir -p "${REPOS_DIR}" "${DATA_DIR}"

clone_or_update "${PROMETHEUS_REPO}" "${REPOS_DIR}/prometheus" "${PROMETHEUS_REF}"
clone_or_update "${CLIENT_GOLANG_REPO}" "${REPOS_DIR}/client_golang" "${CLIENT_GOLANG_REF}"
clone_or_update "${ADAPTER_REPO}" "${REPOS_DIR}/prometheus-adapter" "${ADAPTER_REF}"
clone_or_update "${NODE_EXPORTER_REPO}" "${REPOS_DIR}/node_exporter" "${NODE_EXPORTER_REF}"

build_generator

MODULES_ARG="${REPOS_DIR}/client_golang:github.com/prometheus/client_golang:client_golang,${REPOS_DIR}/prometheus-adapter:sigs.k8s.io/prometheus-adapter:adapter,${REPOS_DIR}/node_exporter:github.com/prometheus/node_exporter:node_exporter"

echo "Generating ${OUT_DB}..."
"${PROJECT_ROOT}/cpg-gen" -modules "${MODULES_ARG}" "${REPOS_DIR}/prometheus" "${OUT_DB}"
echo "Done: ${OUT_DB}"
