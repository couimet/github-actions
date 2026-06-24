#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-action-shas.sh"

setup() {
  # test_helper's setup is overridden; replicate its temp-dir creation.
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  # Create a mock gh CLI that succeeds only for SHAs listed in
  # $VALID_SHAS_FILE (one per line). Any other SHA exits 1.
  cat > "$TEST_TEMP_DIR/gh" <<'SCRIPT'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" =~ ^repos/.*/commits/([0-9a-f]{40})$ ]]; then
    sha="${BASH_REMATCH[1]}"
    break
  fi
done
if [[ -n "${sha:-}" ]] && [[ -f "${VALID_SHAS_FILE:-}" ]] && grep -qxF "$sha" "${VALID_SHAS_FILE:-}" 2>/dev/null; then
  echo "{\"sha\":\"$sha\"}"
  exit 0
fi
echo "{\"message\":\"Not Found\",\"documentation_url\":\"https://docs.github.com/rest\"}" >&2
exit 1
SCRIPT
  chmod +x "$TEST_TEMP_DIR/gh"

  # Default: empty valid-shas file (all SHAs are missing)
  touch "$TEST_TEMP_DIR/valid-shas.txt"

  mkdir -p "$TEST_TEMP_DIR/test-action"
}

# Helper: run the script with the mock gh on PATH and ACTION_ROOT in the temp dir.
run_script() {
  run bash -c "
    cd '$TEST_TEMP_DIR' && \
    PATH='$TEST_TEMP_DIR:$PATH' \
    VALID_SHAS_FILE='$TEST_TEMP_DIR/valid-shas.txt' \
    ACTION_ROOT='$TEST_TEMP_DIR' \
    bash '$SCRIPT'
  "
}

SHA1="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# --- tests ---

@test "all SHAs valid -> success" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"
  echo "$SHA2" >> "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    - uses: owner2/repo2@${SHA2}
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 2 pinned SHA(s) verified"
}

@test "one SHA missing -> failure with error message" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    - uses: owner/repo@${SHA2}
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "MISSING"
  echo "$output" | grep -q "::error::SHA ${SHA2} not found"
}

@test "mixed valid and invalid -> failure" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    - uses: owner/repo@${SHA2}
EOF

  run_script
  [ "$status" -ne 0 ]
  # Only one MISSING line
  [ "$(echo "$output" | grep -c 'MISSING')" -eq 1 ]
  echo "$output" | grep -q "OK"
}

@test "no pinned SHAs -> success" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: ./local-action
    - uses: owner/repo@main
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 0 pinned SHA(s) verified"
}

@test "gh CLI not available -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
EOF

  run bash -c "
    cd '$TEST_TEMP_DIR' && \
    PATH='/usr/bin:/bin' \
    ACTION_ROOT='$TEST_TEMP_DIR' \
    bash '$SCRIPT'
  "
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "gh CLI is required"
}
