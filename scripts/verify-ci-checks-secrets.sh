#!/usr/bin/env bash
set -euo pipefail

# Verify ci-checks.yml properly forwards secrets from workflow_call to all four
# jobs. Each job must expose github-token as the GITHUB_TOKEN env var so callers'
# shell commands can use authenticated API access.
#
# Inputs (env):
#   CI_CHECKS_PATH  path to ci-checks.yml (default: <repo_root>/.github/workflows/ci-checks.yml)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CI_CHECKS="${CI_CHECKS_PATH:-$REPO_ROOT/.github/workflows/ci-checks.yml}"

if [[ ! -f "$CI_CHECKS" ]]; then
  echo "::error::ci-checks.yml not found at ${CI_CHECKS}"
  exit 1
fi

violations=0

# --- Check 1: workflow_call declares github-token secret with required: false ---

# Extract the on.workflow_call section (between 'on:' and 'jobs:')
workflow_call="$(sed -n '/^on:/,/^jobs:/p' "$CI_CHECKS")"

# github-token must appear in the workflow_call section (the secrets: block)
if ! echo "$workflow_call" | grep -q 'github-token:'; then
  echo "::error::ci-checks.yml on.workflow_call.secrets is missing github-token"
  violations=$((violations + 1))
fi

# required: false must appear in the workflow_call section (ensures callers
# without a token can still use the workflow)
if ! echo "$workflow_call" | grep -q 'required: false'; then
  echo "::error::ci-checks.yml github-token secret must have required: false"
  violations=$((violations + 1))
fi

# --- Check 2: each of the four jobs forwards the secret via GITHUB_TOKEN env var ---

github_token_env_count=$(grep -c 'GITHUB_TOKEN:' "$CI_CHECKS" || true)
if [[ "$github_token_env_count" -ne 4 ]]; then
  echo "::error::ci-checks.yml should have exactly 4 GITHUB_TOKEN env vars (one per job), found ${github_token_env_count}"
  violations=$((violations + 1))
fi

if (( violations )); then
  echo "::error::${violations} violation(s) found in ci-checks.yml secrets passthrough. Ensure on.workflow_call.secrets declares github-token with required: false, and each job exposes GITHUB_TOKEN as an env var."
  exit 1
fi

echo "ci-checks.yml secrets passthrough verified."
exit 0
