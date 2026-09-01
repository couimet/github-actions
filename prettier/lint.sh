#!/usr/bin/env bash
set -euo pipefail

# Run prettier with optional --config and explicit paths. Configuration is
# resolved per target path (file, directory incl. its subtree, or glob
# base): targets partition into configured and unconfigured, and only
# unconfigured targets receive the bundled canonical @couimet/eslint-config/
# prettier config as a fallback. An explicit CONFIG wins for every target.
#
# Inputs (env):
#   MODE               check (default, --check) or fix (--write)
#   WORKING_DIRECTORY  directory to run in (default: .)
#   CONFIG             path passed as --config (optional)
#   PATHS              space-separated path(s) to check (default: .)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolved via SCRIPT_DIR
source "$SCRIPT_DIR/../scripts/_lint-helpers.sh"

cd "${WORKING_DIRECTORY:-.}"

# Mirror Prettier's own discovery: a config file or a package.json "prettier"
# key found in the working directory or any ancestor counts, so the fallback
# never overrides a config Prettier would resolve for the target files.
has_prettier_config() {
  local dir="$1"
  while true; do
    if compgen -G "$dir/.prettierrc*" > /dev/null \
      || compgen -G "$dir/prettier.config.*" > /dev/null \
      || { [[ -f "$dir/package.json" ]] \
           && node -e 'process.exit(require(process.argv[1]).prettier ? 0 : 1)' "$dir/package.json" 2>/dev/null; }; then
      return 0
    fi
    if [[ "$dir" == "/" ]]; then
      return 1
    fi
    dir="$(dirname "$dir")"
  done
}

# Decide whether Prettier would resolve a repo config for one target path
# (file, directory including its subtree, or glob base). Over-inclusive
# classification is safe: wrongly skipping the fallback yields Prettier's
# own defaults, while wrongly applying the fallback overrides a real repo
# config.
target_has_config() {
  local target="${1%/}"
  local dir
  if [[ -f "$target" ]]; then
    dir="$(dirname "$target")"
  elif [[ -d "$target" ]]; then
    dir="$target"
  elif [[ "$target" == *['*?['{]* ]]; then
    # Glob: Prettier expands it from the nearest literal ancestor, so strip
    # the last path component until no glob characters (wildcards or braces)
    # remain.
    dir="$target"
    while [[ "$dir" == *['*?['{]* ]] && [[ "$dir" == */* ]]; do
      dir="${dir%/*}"
    done
    if [[ "$dir" == *['*?['{]* ]]; then
      dir="."
    fi
  else
    dir="$(dirname "$target")"
  fi

  # has_prettier_config walks dirname until "/", which never terminates on a
  # relative path (dirname "." is "."), so probe from an absolute path.
  if [[ "$dir" != /* ]]; then
    dir="$PWD/$dir"
  fi
  if has_prettier_config "$dir"; then
    return 0
  fi

  # A directory also covers deeper files, so scan its subtree for configs
  # Prettier would resolve for them.
  if [[ -d "$dir" ]]; then
    if find "$dir" -mindepth 1 \
      \( -path '*/node_modules/*' -o -path '*/.git/*' \) -prune \
      -o \( -name '.prettierrc*' -o -name 'prettier.config.*' \) -print -quit \
      | grep -q .; then
      return 0
    fi
    if node -e '
      const fs = require("fs");
      const path = require("path");
      function walk(dir) {
        let entries;
        try {
          entries = fs.readdirSync(dir, { withFileTypes: true });
        } catch (e) {
          return false;
        }
        for (const entry of entries) {
          const full = path.join(dir, entry.name);
          if (entry.isDirectory()) {
            if (entry.name === "node_modules" || entry.name === ".git") continue;
            if (walk(full)) return true;
          } else if (entry.name === "package.json") {
            try {
              const json = JSON.parse(fs.readFileSync(full, "utf8"));
              if (json.prettier) return true;
            } catch (e) {
              // unreadable or malformed package.json: ignore
            }
          }
        }
        return false;
      }
      process.exit(walk(process.argv[1]) ? 0 : 1);
    ' "$dir" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

if [[ "${MODE:-check}" != "check" && "${MODE:-check}" != "fix" ]]; then
  echo "ERROR: MODE must be 'check' or 'fix', got '${MODE}'" >&2
  exit 1
fi

if [[ -n "${CONFIG:-}" ]]; then
  # An explicit --config wins for every target, so a single invocation
  # covers them all.
  if [[ "${MODE:-check}" == "fix" ]]; then
    prettier --write --config "$CONFIG" "${PATH_ARGS[@]}"
  else
    prettier --check --config "$CONFIG" "${PATH_ARGS[@]}"
  fi
else
  # No explicit config: partition the targets by whether Prettier would
  # resolve a repo config for each, keeping the original path strings
  # (trailing slashes included).
  configured=()
  unconfigured=()
  for target in "${PATH_ARGS[@]}"; do
    if target_has_config "$target"; then
      configured+=("$target")
    else
      unconfigured+=("$target")
    fi
  done

  # Unconfigured targets get the bundled canonical config; configured ones
  # run plain so Prettier discovers their config. Both partitions run even
  # in check mode when one fails, so every target gets checked.
  status=0
  if [[ ${#unconfigured[@]} -gt 0 ]]; then
    if [[ "${MODE:-check}" == "fix" ]]; then
      prettier --write --config "$SCRIPT_DIR/node_modules/@couimet/eslint-config/prettier.js" "${unconfigured[@]}" || status=1
    else
      prettier --check --config "$SCRIPT_DIR/node_modules/@couimet/eslint-config/prettier.js" "${unconfigured[@]}" || status=1
    fi
  fi
  if [[ ${#configured[@]} -gt 0 ]]; then
    if [[ "${MODE:-check}" == "fix" ]]; then
      prettier --write "${configured[@]}" || status=1
    else
      prettier --check "${configured[@]}" || status=1
    fi
  fi
  exit $status
fi
