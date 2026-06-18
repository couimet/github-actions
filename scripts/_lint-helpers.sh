#!/usr/bin/env bash
# Shared setup for lint.sh driver scripts. Source this file, then use
# $CONFIG_ARGS and $PATH_ARGS to build the final command line.
#
# Expects these env vars (set by the calling action.yml or driver):
#   CONFIG  optional path passed as --config
#   PATHS   space-separated paths/globs to lint (default: .)
#
# After sourcing:
#   CONFIG_ARGS  empty, or (--config "$CONFIG")
#   PATH_ARGS    word-split array of $PATHS

# shellcheck disable=SC2034  # consumed by sourcing script
CONFIG_ARGS=()
if [[ -n "${CONFIG:-}" ]]; then
  CONFIG_ARGS+=(--config "$CONFIG")
fi

# shellcheck disable=SC2034  # consumed by sourcing script
IFS=' ' read -ra PATH_ARGS <<< "${PATHS:-.}"
