#!/usr/bin/env bash
set -euo pipefail

files="${FILES:-coverage/lcov.info}"
working_dir="${WORKING_DIRECTORY:-.}"
base="${PER_PACKAGE_FLAGS_BASE:-}"
pattern="${PER_PACKAGE_FLAGS_PATTERN:-}"
fail_ci_if_error="${FAIL_CI_IF_ERROR:-false}"

cd "$working_dir"

# Validate pattern doesn't contain dangerous sed flags (defense-in-depth).
# The 'e' flag in GNU sed executes the replacement as a shell command.
if [ -n "$pattern" ]; then
  delim="${pattern:1:1}"
  # Reject patterns that don't start with 's' followed by a delimiter
  if [[ "$pattern" != s"$delim"* ]]; then
    echo "Error: PER_PACKAGE_FLAGS_PATTERN must be a single 's' substitution command" >&2
    exit 1
  fi
  # Reject multi-command patterns (semicolons, newlines)
  if [[ "$pattern" == *";"* || "$pattern" == *$'\n'* ]]; then
    echo "Error: PER_PACKAGE_FLAGS_PATTERN must contain a single substitution command" >&2
    exit 1
  fi
  # Reject the 'e' flag (only meaningful after the last delimiter)
  flags="${pattern##*"$delim"}"
  if [[ "$flags" == *e* ]]; then
    echo "Error: PER_PACKAGE_FLAGS_PATTERN contains unsupported 'e' flag" >&2
    exit 1
  fi
fi

# Phase 1: collect valid (file, flag) pairs before downloading Codecov.
upload_files=()
upload_flags=()
for f in $files; do
  [ -f "$f" ] || continue
  if [ -n "$pattern" ]; then
    pkg=$(echo "$f" | sed "$pattern")
  elif [ -n "$base" ]; then
    prefix="${base%/}/"
    remainder="${f#"$prefix"}"
    if [[ "$remainder" != "$f" && "$remainder" == */* ]]; then
      pkg="${remainder%%/*}"
    else
      pkg=""
    fi
  else
    # Require at least 2 slashes (3+ path components) to extract a
    # meaningful package name. Avoids treating "coverage/lcov.info" as
    # package "coverage".
    pkg=$(echo "$f" | awk -F/ 'NF >= 3 {print $1}')
  fi
  if [ -n "$pkg" ] && [ "$pkg" != "$f" ]; then
    upload_files+=("$f")
    upload_flags+=("$pkg")
  fi
done

# Exit successfully when no package uploads are needed. The repository-wide
# upload in the calling action.yml is the fallback.
[ ${#upload_files[@]} -eq 0 ] && exit 0

# Phase 2: download Codecov and upload each package.
curl -Os https://uploader.codecov.io/latest/linux/codecov
chmod +x codecov

for i in "${!upload_files[@]}"; do
  codecov_args=(-f "${upload_files[$i]}" -F "${upload_flags[$i]}")
  [ "$fail_ci_if_error" = "true" ] && codecov_args+=(-Z)
  ./codecov "${codecov_args[@]}"
done
