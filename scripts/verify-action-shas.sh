#!/usr/bin/env bash
set -euo pipefail

# Verify every uses: reference in this repo's composite actions and workflows.
#
# Two rules are enforced:
#   - CI001: third-party actions must be pinned to a full 40-char commit SHA,
#     never a branch or tag.
#   - CI002: couimet/github-actions/* refs must ride @main, never a commit SHA.
#
# Every surviving pin is then resolved on the remote, so an upstream
# force-push that invalidates a pin fails here rather than in a consumer's CI.
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

# Workflows carry the same uses: rules. The directory is optional so a bare
# ACTION_ROOT (the BATS fixture, or a consumer overriding the root) still runs.
workflow_files=""
if [[ -d "${ACTION_ROOT}/.github/workflows" ]]; then
  if ! workflow_files="$(find "${ACTION_ROOT}/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)"; then
    echo "::error::Failed to enumerate workflow files"
    exit 1
  fi
fi

missing=0
checked=0
violations=0

while IFS= read -r scan_file; do
  [[ -z "$scan_file" ]] && continue

  # Extract every uses: line that carries an @ ref. A line without one is a
  # local ./ or ../ path and needs no validation. The leading "- " is
  # optional: a step usually indents uses: under a "- name:" line, so
  # requiring it would skip every real pin in this repo.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Pull out "owner/repo@<ref>" from a uses: line. The capture stops at
    # whitespace, so a trailing YAML comment is dropped with it.
    ref="$(echo "$line" | sed -n 's/.*uses:[[:space:]]*\([^[:space:]]*@[^[:space:]]*\).*/\1/p')"
    [[ -z "$ref" ]] && continue
    # Strip optional surrounding quotes (single or double) that YAML
    # allows on string values, so the ref stays a clean owner/repo@ref.
    ref="${ref#\"}"; ref="${ref%\"}"
    ref="${ref#\'}"; ref="${ref%\'}"

    # Local paths resolve inside the consuming workspace, so neither pin rule
    # applies to them.
    if [[ "$ref" == ./* || "$ref" == ../* ]]; then
      continue
    fi

    repo="${ref%@*}"
    pin="${ref##*@}"

    # CI002: first-party refs ride the rolling @main channel. A SHA or tag
    # here is exactly the pin-update churn the rule exists to avoid.
    if [[ "$repo" == couimet/github-actions/* ]]; then
      if [[ "$pin" != "main" ]]; then
        echo "::error::${scan_file} references ${ref}. Internal actions must use @main, never a commit SHA or tag."
        violations=$((violations + 1))
      fi
      continue
    fi

    # CI001: everything else is third-party and must be pinned to a full SHA.
    if [[ ! "$pin" =~ ^[0-9a-f]{40}$ ]]; then
      echo "::error::${scan_file} references ${ref}. Pin third-party actions to a full 40-character commit SHA, not a branch or tag."
      violations=$((violations + 1))
      continue
    fi

    checked=$((checked + 1))

    echo -n "Checking ${repo}@${pin:0:7}... "

    if gh api "repos/${repo}/commits/${pin}" --jq '.sha' >/dev/null 2>&1; then
      echo "OK"
    else
      echo "MISSING"
      echo "::error::SHA ${pin} not found in ${repo} (pinned in ${scan_file}). The upstream repo may have force-pushed; update the pin to a current SHA."
      missing=$((missing + 1))
    fi
  done < <(grep -E '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]+[^[:space:]#]+@' "$scan_file")
done <<< "$(printf '%s\n%s\n' "$action_files" "$workflow_files" | grep -v '^$' | sort)"

if (( violations )); then
  echo "::error::${violations} uses: reference(s) violate the pinning rules. Third-party actions need a full commit SHA; couimet/github-actions actions need @main."
fi

if (( missing )); then
  echo "::error::${missing} pinned SHA(s) are missing from their upstream repos. Update the affected file(s)."
fi

if (( violations || missing )); then
  exit 1
fi

echo "All ${checked} pinned SHA(s) verified."
exit 0
