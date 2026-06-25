#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/shellcheck/lint.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/shellcheck" <<'ENDOFSTUB'
#!/usr/bin/env bash
echo "shellcheck args: $*"
exit 0
ENDOFSTUB
  chmod +x "$TEST_TEMP_DIR/bin/shellcheck"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"

  cd "$TEST_TEMP_DIR"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

@test "default inputs: finds .sh and .bash files, excludes default dirs" {
  touch "$TEST_TEMP_DIR/script.sh" "$TEST_TEMP_DIR/helper.bash"
  mkdir -p "$TEST_TEMP_DIR/node_modules/pkg" "$TEST_TEMP_DIR/.claude-work"
  touch "$TEST_TEMP_DIR/node_modules/pkg/other.sh"
  touch "$TEST_TEMP_DIR/.claude-work/something.sh"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "script.sh"
  echo "$output" | grep -q "helper.bash"
  ! echo "$output" | grep -q "other.sh"
  ! echo "$output" | grep -q "something.sh"
}

@test "custom extensions: only lints specified extensions" {
  touch "$TEST_TEMP_DIR/script.sh" "$TEST_TEMP_DIR/helper.bash"

  run env EXTENSIONS="sh" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "script.sh"
  ! echo "$output" | grep -q "helper.bash"
}

@test "custom exclude: excludes user-specified path fragments" {
  touch "$TEST_TEMP_DIR/script.sh"
  mkdir -p "$TEST_TEMP_DIR/vendor/lib"
  touch "$TEST_TEMP_DIR/vendor/lib/thirdparty.sh"

  run env EXCLUDE="vendor .claude-work .history node_modules .git" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "script.sh"
  ! echo "$output" | grep -q "thirdparty.sh"
}

@test "severity: passes --severity flag to shellcheck" {
  touch "$TEST_TEMP_DIR/script.sh"

  run env SEVERITY="error" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "shellcheck args: --severity error"
  echo "$output" | grep -q "script.sh"
}

@test "no matching files: exits successfully without calling shellcheck" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
