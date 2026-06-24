#!/usr/bin/env bash
set -euo pipefail

# Interface (all via environment):
#   TEST_DIRECTORY   - directory containing .bats files (default: tests/)
#   FORMATTER        - optional --formatter value (e.g. tap, junit)
#   RECURSIVE        - "true" to recurse into subdirectories
#   PUBLISH_COMMENT  - "true" to capture results and write a PR comment file
#   GITHUB_OUTPUT    - path to GitHub Actions output file (default: /dev/null)
#   RUNNER_TEMP      - path to runner temp directory (default: /tmp)
#
# When PUBLISH_COMMENT is "true":
#   1. Runs bats with --formatter tap to get reliably parseable output
#   2. Parses TAP to count passed (^ok) and failed (^not ok) lines
#   3. Writes total, passed, failed, exit_code to GITHUB_OUTPUT
#   4. Writes a markdown comment to RUNNER_TEMP/bats-comment.md
#   5. Exits with the bats exit code
#
# The user's FORMATTER input is ignored in publish mode because reliable
# pass/fail counts require TAP output. Use publish-comment=false to keep
# the user's formatter.
#
# When PUBLISH_COMMENT is not "true": runs bats directly.

TEST_DIRECTORY="${TEST_DIRECTORY:-tests/}"
FORMATTER="${FORMATTER:-}"
RECURSIVE="${RECURSIVE:-false}"
PUBLISH_COMMENT="${PUBLISH_COMMENT:-false}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"

# Build bats arguments shared by both paths
args=()
if [[ "$RECURSIVE" == "true" ]]; then args+=(--recursive); fi

# --- Publish path ---------------------------------------------------------
if [[ "$PUBLISH_COMMENT" == "true" ]]; then

  output_file="$RUNNER_TEMP/bats-output.txt"
  set +e
  bats ${args[@]+"${args[@]}"} --formatter tap "$TEST_DIRECTORY" | tee "$output_file"
  exit_code=$?
  set -e

  # Parse TAP: count lines starting with "ok " and "not ok "
  total=$(grep -cE '^(ok|not ok) ' "$output_file" 2>/dev/null) || true
  passed=$(grep -c '^ok ' "$output_file" 2>/dev/null) || true
  failed=$(grep -c '^not ok ' "$output_file" 2>/dev/null) || true
  # Validate; fall back to "?" on parse failure
  if ! [[ "$total" =~ ^[0-9]+$ ]]; then total="?"; fi
  if ! [[ "$passed" =~ ^[0-9]+$ ]]; then passed="?"; fi
  if ! [[ "$failed" =~ ^[0-9]+$ ]]; then failed="?"; fi

  if [[ $total -eq 0 && $exit_code -ne 0 ]]; then
    # BATS error (no TAP output but non-zero exit)
    total="?"
    passed="?"
    failed="?"
  fi
  echo "total=${total}" >> "$GITHUB_OUTPUT"
  echo "exit_code=${exit_code}" >> "$GITHUB_OUTPUT"
  echo "passed=${passed}" >> "$GITHUB_OUTPUT"
  echo "failed=${failed}" >> "$GITHUB_OUTPUT"

  if [[ "$exit_code" -eq 0 ]]; then
    result_emoji="✅ Passed"
  else
    result_emoji="❌ Failed"
  fi

  comment_file="$RUNNER_TEMP/bats-comment.md"
  cat > "$comment_file" << BATS_COMMENT_EOF
## BATS Test Results

| Metric | Count |
|--------|-------|
| Total tests | ${total} |
| Passed | ${passed} |
| Failed | ${failed} |
| Result | ${result_emoji} |

**Test directory:** \`${TEST_DIRECTORY}\`
BATS_COMMENT_EOF

  exit $exit_code
fi

# --- Non-publish path -----------------------------------------------------
if [[ -n "$FORMATTER" ]]; then args+=(--formatter "$FORMATTER"); fi
bats ${args[@]+"${args[@]}"} "$TEST_DIRECTORY"
