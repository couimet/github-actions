#!/usr/bin/env bash
set -euo pipefail

# Verify that every top-level directory containing an action.yml has a
# uses: ./<dir> reference in the CI workflow.
#
# Inputs (env):
#   CI_YML_PATH  path to the CI workflow (default: .github/workflows/ci.yml)

CI_YML_PATH="${CI_YML_PATH:-.github/workflows/ci.yml}"

if [[ ! -f "$CI_YML_PATH" ]]; then
  echo "::error::CI workflow file not found: ${CI_YML_PATH}"
  exit 1
fi

# Enumerate action directories. Prune node_modules so a vendored action.yml
# at depth 2 is never mistaken for a repo action.
if ! action_dirs="$(find . -maxdepth 2 -path ./node_modules -prune -o -name action.yml -print | sort)"; then
  echo "::error::Failed to enumerate action directories"
  exit 1
fi

missing=0
while IFS= read -r action_yml; do
  [[ -z "$action_yml" ]] && continue
  dir="$(basename "$(dirname "$action_yml")")"
  # Skip action.yml at repo root (not a top-level action directory)
  [[ "$dir" == "." ]] && continue
  # Anchored grep: \. escapes the dot, ([[:space:]]|@|$) prevents
  # prefix collisions (e.g. ./setup-node matching ./setup-node-pnpm).
  if ! grep -qE "uses: \./${dir}([[:space:]]|@|$)" "$CI_YML_PATH"; then
    echo "::error::Action directory '${dir}' has no 'uses: ./${dir}' reference in ${CI_YML_PATH}"
    missing=1
  fi
done <<< "$action_dirs"

if (( missing )); then
  echo "::error::One or more action directories are missing from ${CI_YML_PATH}. Add a step with 'uses: ./<dir>' for each."
  exit 1
fi
exit 0
