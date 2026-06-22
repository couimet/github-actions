#!/usr/bin/env bash
set -euo pipefail

working_dir="${WORKING_DIRECTORY:-.}"
coverage_summary_path="${COVERAGE_SUMMARY_PATH:-}"

derive_title() {
  local path="$1"
  local t
  t="$(basename "$(dirname "$(dirname "$path")")")"
  if [[ "$t" == "." || "$t" == "/" || -z "$t" ]]; then
    t="Coverage Report"
  fi
  printf '%s' "$t"
}

cd "$working_dir"

if [[ -n "$coverage_summary_path" ]]; then
  # Single path override: extract title from the directory two levels up.
  # ./packages/foo/coverage/coverage-summary.json -> foo
  title="$(derive_title "$coverage_summary_path")"
  echo "multiple_files=${title}, ${coverage_summary_path}" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Auto-discover all coverage-summary.json files under the working directory,
# excluding node_modules.
maps=$(find . -name coverage-summary.json -not -path '*/node_modules/*' 2>/dev/null || true)

if [[ -z "$maps" ]]; then
  echo "::warning::No coverage-summary.json files found under ${working_dir}"
  echo "multiple_files=" >> "$GITHUB_OUTPUT"
  exit 0
fi

multiple_files=""
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  # Extract title from the directory two levels up from the coverage file.
  # ./packages/rangelink-core-ts/coverage/coverage-summary.json -> rangelink-core-ts
  title="$(derive_title "$file")"
  multiple_files+="${title}, ${file}"$'\n'
done <<< "$maps"

# Trim trailing newline
multiple_files="${multiple_files%$'\n'}"

# Multi-line output via heredoc for GITHUB_OUTPUT
{
  echo "multiple_files<<EOF"
  echo "$multiple_files"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
