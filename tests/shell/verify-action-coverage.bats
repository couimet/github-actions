#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-action-coverage.sh"

@test "all actions covered -> success" {
  mkdir -p "$TEST_TEMP_DIR/foo" "$TEST_TEMP_DIR/bar"
  touch "$TEST_TEMP_DIR/foo/action.yml" "$TEST_TEMP_DIR/bar/action.yml"
  cat > "$TEST_TEMP_DIR/ci.yml" <<'EOF'
steps:
  - uses: ./foo
  - uses: ./bar
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && CI_YML_PATH=ci.yml bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "missing action -> failure with error message" {
  mkdir -p "$TEST_TEMP_DIR/foo" "$TEST_TEMP_DIR/bar"
  touch "$TEST_TEMP_DIR/foo/action.yml" "$TEST_TEMP_DIR/bar/action.yml"
  cat > "$TEST_TEMP_DIR/ci.yml" <<'EOF'
steps:
  - uses: ./foo
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && CI_YML_PATH=ci.yml bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "has no 'uses: ./bar' reference"
}

@test "missing CI workflow file -> failure" {
  run bash -c "CI_YML_PATH=/nonexistent/ci.yml bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "CI workflow file not found"
}

@test "root-level action.yml is skipped (not a composite action dir)" {
  mkdir -p "$TEST_TEMP_DIR/foo"
  touch "$TEST_TEMP_DIR/action.yml"
  touch "$TEST_TEMP_DIR/foo/action.yml"
  cat > "$TEST_TEMP_DIR/ci.yml" <<'EOF'
steps:
  - uses: ./foo
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && CI_YML_PATH=ci.yml bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "prefix collision: one action name is a prefix of another -> catches missing" {
  mkdir -p "$TEST_TEMP_DIR/setup-node" "$TEST_TEMP_DIR/setup-node-pnpm"
  touch "$TEST_TEMP_DIR/setup-node/action.yml" "$TEST_TEMP_DIR/setup-node-pnpm/action.yml"
  cat > "$TEST_TEMP_DIR/ci.yml" <<'EOF'
steps:
  - uses: ./setup-node-pnpm
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && CI_YML_PATH=ci.yml bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "has no 'uses: ./setup-node' reference"
}
