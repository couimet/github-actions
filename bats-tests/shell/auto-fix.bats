#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/auto-fix/fix.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  cd "$TEST_TEMP_DIR"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# --- running the fix command ---

@test "runs the fix command in WORKING_DIRECTORY" {
  run env FIX_COMMAND='touch result.txt' WORKING_DIRECTORY="$TEST_TEMP_DIR" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/result.txt" ]
}

@test "runs the fix command inside WORKING_DIRECTORY" {
  run env FIX_COMMAND='pwd > cwd.txt' WORKING_DIRECTORY="$TEST_TEMP_DIR" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/cwd.txt")" = "$TEST_TEMP_DIR" ]
}

@test "propagates a non-zero exit code from the fix command" {
  run env FIX_COMMAND='false' WORKING_DIRECTORY="$TEST_TEMP_DIR" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "defaults to the current directory when WORKING_DIRECTORY is unset" {
  run env FIX_COMMAND='pwd > cwd.txt' bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/cwd.txt")" = "$TEST_TEMP_DIR" ]
}

@test "empty FIX_COMMAND fails with an error message" {
  run env WORKING_DIRECTORY="$TEST_TEMP_DIR" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "error: FIX_COMMAND is required"
}
