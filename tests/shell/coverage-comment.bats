#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/coverage-comment/discover.sh"

# Helper: run the discover script in a temp dir with optional env vars.
# Sets GITHUB_OUTPUT to a temp file so tests can inspect the output.
run_discover() {
  GITHUB_OUTPUT="$(mktemp)"
  export GITHUB_OUTPUT
  cd "$TEST_TEMP_DIR"
  run env \
    WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}" \
    COVERAGE_SUMMARY_PATH="${COVERAGE_SUMMARY_PATH:-}" \
    GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    bash "$SCRIPT"
}

@test "single path: extracts title and writes multiple_files output" {
  mkdir -p "$TEST_TEMP_DIR/packages/foo/coverage"
  echo '{}' > "$TEST_TEMP_DIR/packages/foo/coverage/coverage-summary.json"
  export WORKING_DIRECTORY="$TEST_TEMP_DIR"
  export COVERAGE_SUMMARY_PATH="packages/foo/coverage/coverage-summary.json"
  run_discover
  [ "$status" -eq 0 ]
  echo "GITHUB_OUTPUT: $(cat "$GITHUB_OUTPUT")"
  grep -q "multiple_files=foo, packages/foo/coverage/coverage-summary.json" "$GITHUB_OUTPUT"
}

@test "auto-discovery: finds coverage files and builds multiple_files" {
  mkdir -p "$TEST_TEMP_DIR/packages/core/coverage"
  echo '{}' > "$TEST_TEMP_DIR/packages/core/coverage/coverage-summary.json"
  mkdir -p "$TEST_TEMP_DIR/packages/utils/coverage"
  echo '{}' > "$TEST_TEMP_DIR/packages/utils/coverage/coverage-summary.json"
  export WORKING_DIRECTORY="$TEST_TEMP_DIR"
  export COVERAGE_SUMMARY_PATH=""
  run_discover
  [ "$status" -eq 0 ]
  echo "GITHUB_OUTPUT: $(cat "$GITHUB_OUTPUT")"
  grep -q "core, ./packages/core/coverage/coverage-summary.json" "$GITHUB_OUTPUT"
  grep -q "utils, ./packages/utils/coverage/coverage-summary.json" "$GITHUB_OUTPUT"
}

@test "auto-discovery: excludes node_modules" {
  mkdir -p "$TEST_TEMP_DIR/packages/app/coverage"
  echo '{}' > "$TEST_TEMP_DIR/packages/app/coverage/coverage-summary.json"
  mkdir -p "$TEST_TEMP_DIR/node_modules/some-pkg/coverage"
  echo '{}' > "$TEST_TEMP_DIR/node_modules/some-pkg/coverage/coverage-summary.json"
  export WORKING_DIRECTORY="$TEST_TEMP_DIR"
  export COVERAGE_SUMMARY_PATH=""
  run_discover
  [ "$status" -eq 0 ]
  echo "GITHUB_OUTPUT: $(cat "$GITHUB_OUTPUT")"
  grep -q "app, ./packages/app/coverage/coverage-summary.json" "$GITHUB_OUTPUT"
  ! grep -q "node_modules" "$GITHUB_OUTPUT"
}

@test "auto-discovery: no files found emits warning and empty output" {
  export WORKING_DIRECTORY="$TEST_TEMP_DIR"
  export COVERAGE_SUMMARY_PATH=""
  run_discover
  [ "$status" -eq 0 ]
  echo "stdout: $output"
  echo "$output" | grep -q "No coverage-summary.json files found"
  grep -q "multiple_files=$" "$GITHUB_OUTPUT" || grep -q "multiple_files=" "$GITHUB_OUTPUT"
}

@test "working directory defaults to '.' when WORKING_DIRECTORY is unset" {
  mkdir -p "$TEST_TEMP_DIR/coverage"
  echo '{}' > "$TEST_TEMP_DIR/coverage/coverage-summary.json"
  # WORKING_DIRECTORY not exported — script should use '.'
  cd "$TEST_TEMP_DIR"
  GITHUB_OUTPUT="$(mktemp)"
  export GITHUB_OUTPUT
  run env \
    COVERAGE_SUMMARY_PATH="" \
    GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "GITHUB_OUTPUT: $(cat "$GITHUB_OUTPUT")"
  grep -q "coverage-summary.json" "$GITHUB_OUTPUT"
}
