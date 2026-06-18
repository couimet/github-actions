#!/usr/bin/env bash
set -euo pipefail

# Run markdownlint-cli2 with optional --config and explicit globs.
#
# Inputs (env):
#   CONFIG  path to a config file passed as --config (optional)
#   GLOBS   glob(s) of Markdown files to lint

args=()
if [[ -n "${CONFIG:-}" ]]; then
  args+=(--config "$CONFIG")
fi

markdownlint-cli2 ${args[@]+"${args[@]}"} "${GLOBS:?GLOBS is required}"
