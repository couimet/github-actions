#!/usr/bin/env bash
set -euo pipefail

SCAN_PATH="${SCAN_PATH:-.}"
BASE_REF="${BASE_REF:-}"
FILE_EXTENSIONS="${FILE_EXTENSIONS:-ts,tsx,js,jsx,mjs,cjs,py,rb,go,rs,java,cs,sh,bash,yaml,yml,toml,md,html,css,scss,sql,tf,graphql,vue,svelte}"

GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

readonly EXCLUDE_DIR_ARGS=(
  --exclude-dir=node_modules
  --exclude-dir=.git
  --exclude-dir=dist
  --exclude-dir=build
  --exclude-dir=coverage
  --exclude-dir=.next
  --exclude-dir=target
  --exclude-dir=__pycache__
  --exclude-dir=out
  --exclude-dir=.vscode-test
)

_count_current() {
  local include_args=()
  local IFS=','
  local ext
  for ext in $FILE_EXTENSIONS; do
    [[ -z "$ext" ]] && continue
    include_args+=(--include="*.${ext}")
  done

  grep -r -E "TODO|FIXME" "$SCAN_PATH" \
    "${include_args[@]}" \
    "${EXCLUDE_DIR_ARGS[@]}" \
    2>/dev/null \
    | wc -l \
    | tr -d ' ' \
    || true
}

_count_base() {
  local ext_pattern
  ext_pattern=$(echo "$FILE_EXTENSIONS" | tr ',' '|')

  git grep -c -E "TODO|FIXME" FETCH_HEAD -- "$SCAN_PATH" 2>/dev/null \
    | grep -E ":[^:]+\.(${ext_pattern}):" \
    | awk -F: '{s+=$NF} END {print s+0}' \
    || true
}

main() {
  local current_count
  current_count=$(_count_current)
  echo "todo-count=$current_count" >> "$GITHUB_OUTPUT"
  echo "Current TODO/FIXME count: $current_count"

  if [[ -z "$BASE_REF" ]]; then
    {
      echo "## TODO/FIXME Analysis"
      echo ""
      echo "- **Current count:** $current_count"
      echo ""
      echo "_No base branch comparison (direct push to main)_"
    } >> "$GITHUB_STEP_SUMMARY"
    return 0
  fi

  echo "Fetching base ref: $BASE_REF"
  git fetch origin "$BASE_REF" --depth=1

  local base_count
  base_count=$(_count_base)
  echo "Base TODO/FIXME count: $base_count"

  local delta
  delta=$((current_count - base_count))

  echo "todo-delta=$delta" >> "$GITHUB_OUTPUT"
  echo "Delta: $delta"

  local comment_file
  comment_file="$(mktemp)"

  {
    echo "## TODO/FIXME Analysis"
    echo ""
    echo "- **Base branch (\`$BASE_REF\`):** $base_count"
    echo "- **Current branch:** $current_count"

    if [[ "$delta" -gt 0 ]]; then
      echo "- **Change:** ⚠️ +$delta (increased)"
    elif [[ "$delta" -lt 0 ]]; then
      echo "- **Change:** ✅ $delta (decreased)"
    else
      echo "- **Change:** ➖ No change"
    fi
  } | tee -a "$GITHUB_STEP_SUMMARY" > "$comment_file"

  echo "comment-file=$comment_file" >> "$GITHUB_OUTPUT"
}

main
