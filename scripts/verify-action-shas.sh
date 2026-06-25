#!/usr/bin/env bash
set -euo pipefail

# Verify that every pinned Git SHA in action.yml uses: lines exists on the
# remote. Catches upstream force-pushes that invalidate pinned SHAs before
# consumers see a broken action referencing a missing commit.
#
# Inputs (env):
#   ACTION_ROOT  dir containing action subdirectories (default: <repo_root>)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ACTION_ROOT="${ACTION_ROOT:-$REPO_ROOT}"

if ! command -v gh &>/dev/null; then
  echo "::error::gh CLI is required but not found. Install it: brew install gh"
  exit 1
fi

# Enumerate action.yml files. Prune node_modules so a vendored action.yml at
# any depth is never mistaken for a repo action.
if ! action_files="$(find "$ACTION_ROOT" -path '*/node_modules' -prune -o -name action.yml -print | sort)"; then
  echo "::error::Failed to enumerate action directories"
  exit 1
fi

missing=0
checked=0

while IFS= read -r action_yml; do
  [[ -z "$action_yml" ]] && continue

  # Extract every uses: line from the action file. Only lines with a
  # full 40-char hex SHA after @ are validated; local paths (./) and
  # branch/tag refs are silently skipped.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Pull out "owner/repo@<40-hex-sha>" from a uses: line. sed -n with
    # the pattern suppresses lines that don't match a pinned SHA.
    ref="$(echo "$line" | sed -n 's/.*uses:[[:space:]]*\([^[:space:]]*@[0-9a-f]\{40\}\).*/\1/p')"
    [[ -z "$ref" ]] && continue
    # Strip optional surrounding quotes (single or double) that YAML
    # allows on string values, so the ref stays a clean owner/repo@sha.
    ref="${ref#\"}"; ref="${ref%\"}"
    ref="${ref#\'}"; ref="${ref%\'}"

    repo="${ref%@*}"
    sha="${ref##*@}"
    checked=$((checked + 1))

    echo -n "Checking ${repo}@${sha:0:7}... "

    if gh api "repos/${repo}/commits/${sha}" --jq '.sha' >/dev/null 2>&1; then
      echo "OK"
    else
      echo "MISSING"
      echo "::error::SHA ${sha} not found in ${repo} (pinned in ${action_yml}). The upstream repo may have force-pushed; update the pin to a current SHA."
      missing=$((missing + 1))
    fi
  done < <(grep -E '^[[:space:]]*-[[:space:]]*uses:[[:space:]]+[^[:space:]]+@[0-9a-f]{40}' "$action_yml")
done <<< "$action_files"

if (( missing )); then
  echo "::error::${missing} pinned SHA(s) are missing from their upstream repos. Update the affected action.yml file(s)."
  exit 1
fi

echo "All ${checked} pinned SHA(s) verified."
exit 0
