#!/usr/bin/env bash
set -euo pipefail

# Detect whether the head commit is an auto-fix commit by comparing the latest
# commit subject with the configured message.
#
# Inputs (env):
#   AUTO_FIX_COMMIT_MESSAGE  commit subject that marks an auto-fix commit

if [[ -z "${AUTO_FIX_COMMIT_MESSAGE:-}" ]]; then
  echo "error: AUTO_FIX_COMMIT_MESSAGE is required" >&2
  exit 1
fi

subject="$(git log -1 --format=%s)"
if [[ "$subject" == "$AUTO_FIX_COMMIT_MESSAGE" ]]; then
  echo "is-auto-fix=true" >> "$GITHUB_OUTPUT"
else
  echo "is-auto-fix=false" >> "$GITHUB_OUTPUT"
fi
