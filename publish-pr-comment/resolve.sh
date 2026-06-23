#!/usr/bin/env bash
set -euo pipefail

PR_NUMBER="${PR_NUMBER:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

if [[ -z "$PR_NUMBER" || "$PR_NUMBER" == "null" ]]; then
  echo "::error::Could not resolve PR number. Pass it via pr-number or run on a pull_request event." >&2
  exit 1
fi

echo "pr_number=${PR_NUMBER}" >> "$GITHUB_OUTPUT"
