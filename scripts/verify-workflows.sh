#!/usr/bin/env bash
set -euo pipefail

# Verify every workflow file with actionlint.
#
# This guards the class of defect that GitHub reports only at run time, and only
# as a whole-file rejection: a reusable-workflow call whose with: value cannot
# be assigned to the declared input type. GitHub coerces a boolean-like literal
# before the assignment, so passing 'false' to a string input fails the entire
# workflow file. Every job then reports startup_failure and none of them runs,
# which reads like an outage rather than a typo. actionlint reports the same
# mismatch locally, at the line, before the push.
#
# actionlint resolves a local `uses: ./...` through git. Outside a git work
# tree it skips that resolution and exits 0 without checking anything, so the
# script refuses to report a pass it cannot trust.
#
# Inputs (env):
#   WORKFLOW_ROOT  dir containing workflow files (default: <repo_root>/.github/workflows)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKFLOW_ROOT="${WORKFLOW_ROOT:-$REPO_ROOT/.github/workflows}"

if ! command -v actionlint &>/dev/null; then
  echo "::error::actionlint is required but not found. Run 'make install-prereqs' to install the pinned version."
  exit 1
fi

if [[ ! -d "$WORKFLOW_ROOT" ]]; then
  echo "::error::workflow directory not found at ${WORKFLOW_ROOT}"
  exit 1
fi

# A silent pass is worse than no check: without a work tree, actionlint cannot
# resolve the local reusable workflows that carry the input types.
if ! git -C "$WORKFLOW_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  echo "::error::${WORKFLOW_ROOT} is not inside a git work tree. actionlint resolves local reusable workflows through git, and would report a pass without checking them."
  exit 1
fi

shopt -s nullglob
workflow_files=("$WORKFLOW_ROOT"/*.yml "$WORKFLOW_ROOT"/*.yaml)
shopt -u nullglob

if (( ${#workflow_files[@]} == 0 )); then
  echo "::error::no workflow files found under ${WORKFLOW_ROOT}"
  exit 1
fi

if output="$(actionlint "${workflow_files[@]}" 2>&1)"; then
  echo "All ${#workflow_files[@]} workflows under ${WORKFLOW_ROOT} pass actionlint."
  exit 0
fi

printf '%s\n' "$output" >&2
echo "::error::actionlint reported workflow problems. GitHub rejects a whole workflow file for an input type mismatch, and every job then reports startup_failure without running."
exit 1
