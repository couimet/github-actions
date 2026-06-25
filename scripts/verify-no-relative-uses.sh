#!/usr/bin/env bash
set -euo pipefail

# Verify that composite action action.yml files never use ./ relative paths to
# reference other actions in this repo. In composite actions, ./ resolves
# relative to the consumer's workspace, so internal refs must use the full
# couimet/github-actions/<name>@main path.
#
# Self-test workflows under .github/workflows/ are exempt — they run in this
# repo and ./ references resolve correctly there.
#
# Inputs (env):
#   ACTION_ROOT  dir containing action subdirectories (default: <repo_root>)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ACTION_ROOT="${ACTION_ROOT:-$REPO_ROOT}"

# Enumerate action directory names (each top-level dir with an action.yml,
# excluding .github/ which contains workflow files, not composite actions).
if ! action_names="$(find "$ACTION_ROOT" -maxdepth 2 -name action.yml -not -path '*/.github/*' -not -path '*/node_modules/*' -exec dirname {} \; | sed 's|.*/||' | sort -u)"; then
  echo "::error::Failed to enumerate action directories"
  exit 1
fi

# Find composite action action.yml files (same scope: top-level dirs, no .github/).
if ! action_files="$(find "$ACTION_ROOT" -maxdepth 2 -name action.yml -not -path '*/.github/*' -not -path '*/node_modules/*' | sort)"; then
  echo "::error::Failed to enumerate action files"
  exit 1
fi

violations=0

while IFS= read -r action_yml; do
  [[ -z "$action_yml" ]] && continue

  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    # Anchored match: \. escapes the dot, ([[:space:]]|@|$) prevents prefix
    # collisions (e.g. ./setup-node matching ./setup-node-pnpm).
    if grep -qE "uses:[[:space:]]+\./${dir}([[:space:]]|@|$)" "$action_yml"; then
      echo "::error::${action_yml} references internal action './${dir}' via relative path. Use 'couimet/github-actions/${dir}@main' instead."
      violations=$((violations + 1))
    fi
  done <<< "$action_names"
done <<< "$action_files"

if (( violations )); then
  echo "::error::${violations} relative uses: reference(s) found in composite action.yml files. Replace ./<dir> with couimet/github-actions/<dir>@main."
  exit 1
fi

echo "All composite actions use full paths for internal references."
exit 0
