#!/usr/bin/env bash
set -euo pipefail

# Discover shell scripts and run shellcheck.
#
# Inputs (env):
#   PATHS       root(s) to search, space-separated (default: .)
#   EXTENSIONS  space-separated file extensions (default: sh bash; empty lints all regular files)
#   EXCLUDE     space-separated path fragments to exclude (default: .claude-work .history node_modules .git)
#   SEVERITY    optional --severity flag value

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolved via SCRIPT_DIR
source "$SCRIPT_DIR/../scripts/_lint-helpers.sh"

EXTENSIONS="${EXTENSIONS-sh bash}"
EXCLUDE="${EXCLUDE-.claude-work .history node_modules .git}"

# Build find -name arguments from space-separated extensions.
ext_arr=()
if [[ -n "$EXTENSIONS" ]]; then
  # read -a unsets the array on empty input, which breaks set -u.
  IFS=' ' read -ra ext_arr <<< "$EXTENSIONS"
fi
name_args=()
if [[ ${#ext_arr[@]} -gt 0 ]]; then
  for ext in "${ext_arr[@]}"; do
    name_args+=(-name "*.$ext" -o)
  done
  unset 'name_args[${#name_args[@]}-1]'
fi

# Build find exclusion arguments from space-separated fragments.
excl_arr=()
if [[ -n "$EXCLUDE" ]]; then
  IFS=' ' read -ra excl_arr <<< "$EXCLUDE"
fi
exclude_args=()
if [[ ${#excl_arr[@]} -gt 0 ]]; then
  for fragment in "${excl_arr[@]}"; do
    [[ -z "$fragment" ]] && continue
    exclude_args+=(-not -path "*/$fragment/*")
  done
fi

# Wrap name args in a ( ) group only when extensions were given;
# an empty ( ) group makes find fail with "empty inner expression".
name_group=()
if [[ ${#name_args[@]} -gt 0 ]]; then
  name_group=(\( "${name_args[@]}" \))
fi

# Build shellcheck severity flag.
severity_args=()
if [[ -n "${SEVERITY:-}" ]]; then
  severity_args+=(--severity "$SEVERITY")
fi

find "${PATH_ARGS[@]}" -type f ${name_group[@]+"${name_group[@]}"} ${exclude_args[@]+"${exclude_args[@]}"} -exec shellcheck ${severity_args[@]+"${severity_args[@]}"} {} +
