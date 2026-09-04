#!/usr/bin/env bash
set -euo pipefail

# Run markdownlint-cli2 with optional --config and explicit paths. With no
# explicit config, the consuming repo's own .markdownlint-cli2.* /
# .markdownlint.* config stays the authority via cli2 auto-discovery; only when
# the repo has no such config (in or under WORKING_DIRECTORY, cli2's search
# bound) does the action fall back to the bundled @couimet/markdownlint-config,
# which enforces MD060 style "aligned" instead of cli2's built-in defaults.
#
# Inputs (env):
#   MODE               check (default, read-only) or fix (adds --fix)
#   CONFIG             path to a config file passed as --config (optional)
#   PATHS              space-separated glob(s) of Markdown files to lint
#   WORKING_DIRECTORY  directory to run in (default: .)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolved via SCRIPT_DIR
source "$SCRIPT_DIR/../scripts/_lint-helpers.sh"

cd "${WORKING_DIRECTORY:-.}"

# Mirror markdownlint-cli2's own discovery: a config file found in the working
# directory or any directory beneath it counts, so the fallback never overrides
# a config cli2 would resolve for the linted files. cli2 searches each file's
# ancestors only up to the invocation directory (WORKING_DIRECTORY) and never
# reads a package.json "markdownlint" key, so configs above it are ignored.
repo_has_markdownlint_config() {
  find "$1" \
    \( -path '*/node_modules/*' -o -path '*/.git/*' \) -prune \
    -o \( \
      -name '.markdownlint-cli2.jsonc' -o -name '.markdownlint-cli2.yaml' \
      -o -name '.markdownlint-cli2.cjs' -o -name '.markdownlint-cli2.mjs' \
      -o -name '.markdownlint.jsonc' -o -name '.markdownlint.json' \
      -o -name '.markdownlint.yaml' -o -name '.markdownlint.yml' \
      -o -name '.markdownlint.cjs' -o -name '.markdownlint.mjs' \
    \) -print -quit | grep -q .
}

if [[ "${MODE:-check}" != "check" && "${MODE:-check}" != "fix" ]]; then
  echo "ERROR: MODE must be 'check' or 'fix', got '${MODE}'" >&2
  exit 1
fi

# Resolve the source config (CONFIG input or auto-discovery), inject the MD060A
# rule, and echo the effective config path. Returns 1 to fall back to today's
# behavior: no config found, a non-JSON config (YAML/CJS/MJS), a missing CONFIG
# file, an unparseable config, or an unresolvable rule.
prepare_fix_config() {
  local source=""
  if [[ -n "${CONFIG:-}" ]]; then
    [[ -f "$CONFIG" ]] || return 1
    source="$CONFIG"
  else
    # Mirror markdownlint-cli2's discovery order.
    local candidate
    for candidate in \
      .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs .markdownlint-cli2.mjs \
      .markdownlint.jsonc .markdownlint.json .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs; do
      if [[ -f "$candidate" ]]; then
        source="$candidate"
        break
      fi
    done
    [[ -n "$source" ]] || return 1
  fi

  # Only JSON/JSONC configs can be parsed and rewritten.
  case "$source" in
    *.json | *.jsonc) ;;
    *) return 1 ;;
  esac

  # The temp file must end with `.markdownlint-cli2.jsonc` for cli2 to parse it
  # as an options file, and must live next to the source so relative extends,
  # customRules, globs, and ignores still resolve. Generate a unique name so the
  # injector never overwrites a consumer config (for example one literally named
  # `tmp.markdownlint-cli2.jsonc`) and the EXIT trap only removes the file this
  # invocation created.
  local base target
  base="$(dirname "$source")"
  while :; do
    target="$base/.tmp.$RANDOM.$RANDOM.markdownlint-cli2.jsonc"
    [[ ! -e "$target" ]] && break
  done
  local injector_output
  if ! injector_output="$(node "$SCRIPT_DIR/inject-rule.cjs" "$source" "$target" 2>/dev/null)"; then
    return 1
  fi
  [[ "$injector_output" == "SKIP" ]] && return 1

  echo "$target"
  return 0
}

FIX_ARGS=()
if [[ "${MODE:-check}" == "fix" ]]; then
  FIX_ARGS+=(--fix)

  # Register markdownlint-rule-force-align-table-columns (MD060A) so --fix can
  # auto-align tables. cli2 only activates custom rules listed in the config it
  # reads, so inject the rule into an effective config passed via --config.
  # Check mode is left untouched: MD060A fires on every table even when MD060 is
  # not configured, so registering it there would newly fail repos that never
  # asked for table-alignment enforcement.
  if effective_config="$(prepare_fix_config)"; then
    CONFIG_ARGS=(--config "$effective_config")
    trap 'rm -f "${effective_config:-}"' EXIT
  fi
fi

# No explicit config and no repo config: apply the bundled canonical
# @couimet/markdownlint-config so table alignment (MD060 "aligned") is enforced
# instead of cli2's built-in defaults, which leave MD060 at "any".
if [[ -z "${CONFIG:-}" ]] && ! repo_has_markdownlint_config "$PWD"; then
  FALLBACK_CONFIG="$SCRIPT_DIR/node_modules/@couimet/markdownlint-config/index.json"
  if [[ -f "$FALLBACK_CONFIG" ]]; then
    CONFIG_ARGS=(--config "$FALLBACK_CONFIG")
  else
    # markdownlint-version override installs -g and no node_modules; keep the
    # pre-fallback behavior (cli2 built-in defaults) rather than fail on ENOENT.
    echo "WARNING: no markdownlint config found and the bundled fallback config is unavailable; using cli2 built-in defaults" >&2
  fi
fi

markdownlint-cli2 ${FIX_ARGS[@]+"${FIX_ARGS[@]}"} ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} "${PATH_ARGS[@]}"
