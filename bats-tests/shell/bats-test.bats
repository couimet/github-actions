#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/bats-test/run.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  TEST_DIR="$TEST_TEMP_DIR/tests"
  mkdir -p "$TEST_DIR"

  export TEST_DIRECTORY="$TEST_DIR"
  export GITHUB_OUTPUT
  GITHUB_OUTPUT="$(mktemp)"
  export RUNNER_TEMP="$TEST_TEMP_DIR"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
  rm -f "$GITHUB_OUTPUT"
}

# --- Non-publish path ------------------------------------------------------

@test "non-publish path: runs bats and exits 0 on success" {
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test 1" { true; }
@test "passing test 2" { true; }
EOF

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "non-publish path: propagates failure exit code" {
  cat > "$TEST_DIR/failing.bats" << 'EOF'
@test "failing test" { false; }
EOF

  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "non-publish path: does not write to GITHUB_OUTPUT" {
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test" { true; }
EOF

  run bash "$SCRIPT"
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "non-publish path: does not create comment file" {
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test" { true; }
EOF

  run bash "$SCRIPT"
  [ ! -f "$RUNNER_TEMP/bats-comment.md" ]
}

@test "non-publish path: passes --formatter to bats" {
  export FORMATTER=tap
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test" { true; }
EOF

  run bash "$SCRIPT"
  [[ "$output" =~ 1\.\.1 ]]
}

@test "non-publish path: passes --recursive" {
  export RECURSIVE=true
  mkdir -p "$TEST_DIR/sub"
  cat > "$TEST_DIR/sub/nested.bats" << 'EOF'
@test "nested test" { true; }
EOF

  run bash "$SCRIPT"
  # Should find and run the nested test
  [[ "$output" =~ "nested test" ]]
}

# --- Publish path ----------------------------------------------------------

@test "publish path: sets total in GITHUB_OUTPUT" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test 1" { true; }
@test "passing test 2" { true; }
EOF

  run bash "$SCRIPT"
  grep -q 'total=2' "$GITHUB_OUTPUT"
}

@test "publish path: sets passed and failed for all-passing" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test" { true; }
EOF

  run bash "$SCRIPT"
  grep -q 'passed=1' "$GITHUB_OUTPUT"
  grep -q 'failed=0' "$GITHUB_OUTPUT"
}

@test "publish path: sets correct passed/failed for mixed results" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/mixed.bats" << 'EOF'
@test "passing test" { true; }
@test "failing test" { false; }
EOF

  run bash "$SCRIPT"
  grep -q 'total=2' "$GITHUB_OUTPUT"
  grep -q 'passed=1' "$GITHUB_OUTPUT"
  grep -q 'failed=1' "$GITHUB_OUTPUT"
}

@test "publish path: exits non-zero when any test fails" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/failing.bats" << 'EOF'
@test "fail 1" { false; }
@test "fail 2" { false; }
@test "pass 1" { true; }
EOF

  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  # TAP parsing still counts individual failures correctly
  grep -q 'total=3' "$GITHUB_OUTPUT"
  grep -q 'passed=1' "$GITHUB_OUTPUT"
  grep -q 'failed=2' "$GITHUB_OUTPUT"
}

@test "publish path: exits 0 when all tests pass" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test" { true; }
EOF

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "publish path: creates comment file" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test" { true; }
EOF

  run bash "$SCRIPT"
  [ -f "$RUNNER_TEMP/bats-comment.md" ]
}

@test "comment file: contains expected structure and values" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "my test" { true; }
EOF

  run bash "$SCRIPT"
  grep -q '## BATS Test Results' "$RUNNER_TEMP/bats-comment.md"
  grep -q '| Total tests | 1 |' "$RUNNER_TEMP/bats-comment.md"
  grep -q '| Passed | 1 |' "$RUNNER_TEMP/bats-comment.md"
  grep -q '| Failed | 0 |' "$RUNNER_TEMP/bats-comment.md"
  grep -q '✅ Passed' "$RUNNER_TEMP/bats-comment.md"
}

@test "comment file: shows failed result emoji on failure" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/failing.bats" << 'EOF'
@test "fail" { false; }
EOF

  run bash "$SCRIPT"
  grep -q '❌ Failed' "$RUNNER_TEMP/bats-comment.md"
}

@test "publish path: captures TAP output regardless of FORMATTER" {
  export PUBLISH_COMMENT=true
  export FORMATTER=junit
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing" { true; }
EOF

  run bash "$SCRIPT"
  # TAP is always used in publish mode, even when FORMATTER is set
  grep -q '1..1' "$RUNNER_TEMP/bats-output.txt"
  grep -q '^ok 1' "$RUNNER_TEMP/bats-output.txt"
}

@test "publish path: passes --recursive" {
  export PUBLISH_COMMENT=true
  export RECURSIVE=true
  mkdir -p "$TEST_DIR/sub"
  cat > "$TEST_DIR/sub/nested.bats" << 'EOF'
@test "nested test" { true; }
EOF

  run bash "$SCRIPT"
  grep -q 'total=1' "$GITHUB_OUTPUT"
}

@test "publish path: handles nonexistent test directory gracefully" {
  export PUBLISH_COMMENT=true
  export TEST_DIRECTORY="/nonexistent/path"

  run bash "$SCRIPT"
  # BATS error: no TAP output → all counts show "?"
  grep -q 'total=?' "$GITHUB_OUTPUT"
  grep -q 'passed=?' "$GITHUB_OUTPUT"
  grep -q 'failed=?' "$GITHUB_OUTPUT"
}

@test "publish path: sets exit_code in GITHUB_OUTPUT" {
  export PUBLISH_COMMENT=true
  cat > "$TEST_DIR/passing.bats" << 'EOF'
@test "passing test" { true; }
EOF

  run bash "$SCRIPT"
  grep -q 'exit_code=0' "$GITHUB_OUTPUT"
}
