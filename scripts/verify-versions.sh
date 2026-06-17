#!/usr/bin/env bash
set -euo pipefail

# Verify that resolved Node.js and pnpm versions match the repo's fixture files.
#
# Inputs (env):
#   NODE_VERSION_OUTPUT  resolved Node version (e.g. "v24.3.1")
#   PNPM_VERSION_OUTPUT  resolved pnpm version (e.g. "9.1.0")
#   CACHE_HIT            optional, echoed for diagnostics
#
# Expected-version sources (overridable for tests):
#   NVMRC_PATH           path to .nvmrc        (default: .nvmrc)
#   PACKAGE_JSON_PATH    path to package.json  (default: tests/package.json)

NVMRC_PATH="${NVMRC_PATH:-.nvmrc}"
PACKAGE_JSON_PATH="${PACKAGE_JSON_PATH:-tests/package.json}"

expected_node="$(tr -d '[:space:]' < "$NVMRC_PATH")"
expected_node="${expected_node#v}"
actual_node="${NODE_VERSION_OUTPUT#v}"
expected_pnpm="$(jq -r '.packageManager' "$PACKAGE_JSON_PATH" | sed 's/^pnpm@//')"

echo "Resolved Node version : ${NODE_VERSION_OUTPUT} (expected ${expected_node}[.x.y])"
echo "Resolved pnpm version : ${PNPM_VERSION_OUTPUT} (expected ${expected_pnpm})"
echo "Cache hit              : ${CACHE_HIT:-}"

case "$actual_node" in
  "$expected_node"|"$expected_node".*) ;;
  *)
    echo "::error::Node version mismatch: expected ${expected_node}[.x.y], got ${actual_node}"
    exit 1
    ;;
esac

if [[ "$PNPM_VERSION_OUTPUT" != "$expected_pnpm" ]]; then
  echo "::error::pnpm version mismatch: expected ${expected_pnpm}, got ${PNPM_VERSION_OUTPUT}"
  exit 1
fi

exit 0
