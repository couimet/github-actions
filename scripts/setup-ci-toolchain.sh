#!/usr/bin/env bash
set -euo pipefail

# Install the tools this repository's BATS suites and guards need, on a runner
# that holds none of them.
#
# This script is the CI twin of `make install-prereqs`. Both read mise.toml,
# which is the single source of truth for the pinned tool versions. The audience
# differs: `make install-prereqs` tells a developer to activate mise in their
# shell, while a workflow step has no shell to activate and needs the tools on
# PATH for the steps that follow.
#
# Call it from the `setup` input of a reusable workflow, or from any step that
# precedes a BATS run. It is idempotent, so a runner that already holds the
# toolchain pays only the checks.
#
# Why mise carries no version pin: mise.toml pins every tool, and those pins are
# what make the test environment reproducible. mise is the installer, and the
# repository's other provisioning path, the setup-mise action, does not pin it
# either. A stale mise cannot resolve a newly pinned tool version, so a pin here
# would buy a bump chore and a new failure mode.
#
# Inputs (env):
#   TOOLCHAIN_ROOT  optional. Directory holding mise.toml and the markdownlint
#                   action. Default: the parent of this script.
#   GITHUB_PATH     optional. Appended to when set, so the workflow steps that
#                   follow this one see the tools.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-$(dirname "$SCRIPT_DIR")}"

MISE_TOML="${TOOLCHAIN_ROOT}/mise.toml"
MARKDOWNLINT_DIR="${TOOLCHAIN_ROOT}/markdownlint"

# mise installs here, and the installer adds the directory to no PATH of this
# process.
MISE_BIN_DIR="${HOME}/.local/bin"

if [[ ! -f "$MISE_TOML" ]]; then
  echo "::error::setup-ci-toolchain: no mise.toml at '${MISE_TOML}', so this script cannot read the tool pins." >&2
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  echo "setup-ci-toolchain: mise is absent; installing it."
  if ! command -v curl >/dev/null 2>&1; then
    echo "::error::setup-ci-toolchain: mise is absent and curl is not installed, so the installer cannot run. Install mise first: https://mise.jdx.dev/getting-started.html" >&2
    exit 1
  fi
  # The installer checks the checksum of the release it downloads.
  curl -fsSL https://mise.run | sh
fi

export PATH="${MISE_BIN_DIR}:${PATH}"

if ! command -v mise >/dev/null 2>&1; then
  echo "::error::setup-ci-toolchain: the mise installer ran, but mise still does not resolve on PATH. Expected it in '${MISE_BIN_DIR}'." >&2
  exit 1
fi

# mise reads mise.toml from the working directory, so run the install from the
# directory that holds the file.
cd "$TOOLCHAIN_ROOT"
mise install

# mise bin-paths prints the directory holding each pinned tool's binary. Those
# directories go on PATH for this script, and into GITHUB_PATH for the workflow
# steps that follow, which run in a process this script does not own.
if ! bin_paths="$(mise bin-paths)"; then
  echo "::error::setup-ci-toolchain: 'mise bin-paths' failed, so this script cannot put the pinned tools on PATH." >&2
  exit 1
fi

tool_bin_paths=""
while IFS= read -r tool_dir; do
  if [[ -z "$tool_dir" ]]; then continue; fi
  tool_bin_paths="${tool_bin_paths:+${tool_bin_paths}:}${tool_dir}"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$tool_dir" >> "$GITHUB_PATH"
  fi
done <<< "$bin_paths"
export PATH="${tool_bin_paths}:${PATH}"

# The tool list comes from mise.toml rather than from a copy in this file, so a
# new pin is provisioned and checked without an edit here.
tools="$(awk '
  /^\[tools\]/ { in_tools = 1; next }
  /^\[/ { in_tools = 0 }
  in_tools && /^[A-Za-z0-9_-]+[[:space:]]*=/ { sub(/[[:space:]]*=.*$/, ""); print }
' "$MISE_TOML")"

if [[ -z "$tools" ]]; then
  echo "::error::setup-ci-toolchain: '${MISE_TOML}' declares no tool, so this script checked nothing." >&2
  exit 1
fi

missing=""
count=0
for tool in $tools; do
  count=$((count + 1))
  command -v "$tool" >/dev/null 2>&1 || missing="${missing} ${tool}"
done

if [[ -n "$missing" ]]; then
  echo "::error::setup-ci-toolchain: mise installed the pinned tools, but these do not resolve on PATH:${missing}. Check the mise.toml pin, then run 'mise install' again." >&2
  exit 1
fi

# The markdownlint suite reads the bundled zero-config fallback out of the
# action's node_modules, so that directory must exist before the suite runs.
# `make lint-md` builds it the same way, and skips the install when it is there.
if [[ -d "$MARKDOWNLINT_DIR" && ! -d "${MARKDOWNLINT_DIR}/node_modules" ]]; then
  echo "setup-ci-toolchain: installing the markdownlint action dependencies."
  (cd "$MARKDOWNLINT_DIR" && npm ci --no-audit --no-fund)
fi

echo "setup-ci-toolchain: ${count} pinned tool(s) resolve on PATH."
