#!/usr/bin/env bash
set -euo pipefail

CREATE_NEW="${CREATE_NEW:-false}"
HEADER="${HEADER:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

if [[ "$CREATE_NEW" == "true" ]]; then
  echo "header=${HEADER}-${GITHUB_RUN_ID}" >> "$GITHUB_OUTPUT"
else
  echo "header=${HEADER}" >> "$GITHUB_OUTPUT"
fi
