#!/usr/bin/env bash
set -euo pipefail

files="${FILES:-coverage/lcov.info}"
working_dir="${WORKING_DIRECTORY:-.}"
base="${PER_PACKAGE_FLAGS_BASE:-}"
pattern="${PER_PACKAGE_FLAGS_PATTERN:-}"
fail_ci_if_error="${FAIL_CI_IF_ERROR:-false}"

cd "$working_dir"

curl -Os https://uploader.codecov.io/latest/linux/codecov
chmod +x codecov

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
    codecov_args=(-f "$f" -F "$pkg")
    [ "$fail_ci_if_error" = "true" ] && codecov_args+=(-Z)
    ./codecov "${codecov_args[@]}"
  fi
done
