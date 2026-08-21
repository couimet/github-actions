#!/usr/bin/env bash
set -euo pipefail

# Interface (all via environment):
#   SCHEMA - path to the JSON Schema file, relative to GITHUB_WORKSPACE
#   FILE   - path to the YAML file to validate, relative to GITHUB_WORKSPACE
#
# GITHUB_ACTION_PATH and GITHUB_WORKSPACE are set automatically by the GitHub
# runner for composite action steps. This wrapper sets up the uv environment
# and delegates the validation itself to validate.sh, which also writes the
# comment-file output consumed by action.yml.

cd "$GITHUB_ACTION_PATH"
uv sync --locked
uv run --locked ./validate.sh "$GITHUB_WORKSPACE/$SCHEMA" "$GITHUB_WORKSPACE/$FILE"
