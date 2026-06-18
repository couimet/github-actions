#!/usr/bin/env bash
set -euo pipefail

# Run markdownlint-cli2 with optional --config and explicit globs.
#
# Inputs (env):
#   CONFIG  path to a config file passed as --config (optional)
#   GLOBS   whitespace-separated glob(s) of Markdown files to lint

args=()
if [[ -n "${CONFIG:-}" ]]; then
  args+=(--config "$CONFIG")
fi

IFS=' ' read -ra glob_args <<< "${GLOBS:?GLOBS is required}"
markdownlint-cli2 ${args[@]+"${args[@]}"} "${glob_args[@]}"
