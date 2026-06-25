#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-no-relative-uses.sh"

@test "all full paths -> success" {
  mkdir -p "$TEST_TEMP_DIR/foo" "$TEST_TEMP_DIR/bar"
  cat > "$TEST_TEMP_DIR/foo/action.yml" <<'EOF'
steps:
  - uses: couimet/github-actions/bar@main
EOF
  cat > "$TEST_TEMP_DIR/bar/action.yml" <<'EOF'
steps:
  - uses: couimet/github-actions/foo@main
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && ACTION_ROOT='$TEST_TEMP_DIR' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "relative ./ reference -> failure with error message" {
  mkdir -p "$TEST_TEMP_DIR/foo" "$TEST_TEMP_DIR/bar"
  touch "$TEST_TEMP_DIR/foo/action.yml"
  cat > "$TEST_TEMP_DIR/bar/action.yml" <<'EOF'
steps:
  - uses: ./foo
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && ACTION_ROOT='$TEST_TEMP_DIR' bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references internal action './foo' via relative path"
}

@test "multiple violations -> reports count and fails" {
  mkdir -p "$TEST_TEMP_DIR/foo" "$TEST_TEMP_DIR/bar" "$TEST_TEMP_DIR/baz"
  touch "$TEST_TEMP_DIR/foo/action.yml" "$TEST_TEMP_DIR/bar/action.yml"
  cat > "$TEST_TEMP_DIR/baz/action.yml" <<'EOF'
steps:
  - uses: ./foo
  - uses: ./bar
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && ACTION_ROOT='$TEST_TEMP_DIR' bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references internal action './foo' via relative path"
  echo "$output" | grep -q "references internal action './bar' via relative path"
  echo "$output" | grep -q "2 relative uses: reference(s) found"
}

@test "./ in .github/ is excluded from scan" {
  mkdir -p "$TEST_TEMP_DIR/foo" "$TEST_TEMP_DIR/.github/workflows"
  touch "$TEST_TEMP_DIR/foo/action.yml"
  # This uses ./foo in a workflow context (valid for self-test), but it's under
  # .github/ so the script should not scan it at all.
  cat > "$TEST_TEMP_DIR/.github/workflows/ci.yml" <<'EOF'
steps:
  - uses: ./foo
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && ACTION_ROOT='$TEST_TEMP_DIR' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "prefix collision: one action name is a prefix of another -> catches only exact match" {
  mkdir -p "$TEST_TEMP_DIR/setup-node" "$TEST_TEMP_DIR/setup-node-pnpm"
  touch "$TEST_TEMP_DIR/setup-node/action.yml"
  cat > "$TEST_TEMP_DIR/setup-node-pnpm/action.yml" <<'EOF'
steps:
  - uses: ./setup-node
EOF
  run bash -c "cd '$TEST_TEMP_DIR' && ACTION_ROOT='$TEST_TEMP_DIR' bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references internal action './setup-node' via relative path"
  # setup-node-pnpm itself should NOT be flagged as a referenced action (it wasn't used)
  ! echo "$output" | grep -q "references internal action './setup-node-pnpm'"
}

@test "no action files -> success" {
  mkdir -p "$TEST_TEMP_DIR"
  run bash -c "cd '$TEST_TEMP_DIR' && ACTION_ROOT='$TEST_TEMP_DIR' bash '$SCRIPT'"
  [ "$status" -eq 0 ]
}
