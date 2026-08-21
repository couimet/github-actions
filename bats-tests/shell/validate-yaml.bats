#!/usr/bin/env bats

load test_helper

ACTION_DIR="$PROJECT_ROOT/validate-yaml"
FIXTURES="$ACTION_DIR/tests/fixtures"
VALIDATE="$ACTION_DIR/validate.sh"
SCHEMA="$FIXTURES/valid.schema.json"
VALID="$FIXTURES/valid.yml"
INVALID="$FIXTURES/invalid-missing-context.yml"
MALFORMED="$FIXTURES/malformed.yml"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  GITHUB_OUTPUT="$(mktemp)"
  export GITHUB_OUTPUT
  cd "$ACTION_DIR"
  uv sync --locked --quiet
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
  rm -f "${GITHUB_OUTPUT:?}"
}

@test "valid YAML file passes validation" {
  run uv run --locked "$VALIDATE" "$SCHEMA" "$VALID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "invalid YAML file fails validation" {
  run uv run --locked "$VALIDATE" "$SCHEMA" "$INVALID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR:"* ]]
}

@test "malformed YAML file fails with clean error" {
  run uv run --locked "$VALIDATE" "$SCHEMA" "$MALFORMED"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR:"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "messages use repo-relative path under GITHUB_WORKSPACE" {
  export GITHUB_WORKSPACE="$PROJECT_ROOT"
  run uv run --locked "$VALIDATE" "$SCHEMA" "$VALID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: validate-yaml/tests/fixtures/valid.yml"* ]]

  run uv run --locked "$VALIDATE" "$SCHEMA" "$INVALID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: validate-yaml/tests/fixtures/invalid-missing-context.yml"* ]]
}

@test "schema violation writes comment file" {
  run uv run --locked "$VALIDATE" "$SCHEMA" "$INVALID"
  [ "$status" -eq 1 ]
  grep -q "^comment-file=" "$GITHUB_OUTPUT"
  comment_file="$(grep "^comment-file=" "$GITHUB_OUTPUT" | sed 's/^comment-file=//')"
  [ -f "$comment_file" ]
  grep -q "ERROR:" "$comment_file"
}

@test "malformed YAML writes comment file" {
  run uv run --locked "$VALIDATE" "$SCHEMA" "$MALFORMED"
  [ "$status" -eq 1 ]
  grep -q "^comment-file=" "$GITHUB_OUTPUT"
  comment_file="$(grep "^comment-file=" "$GITHUB_OUTPUT" | sed 's/^comment-file=//')"
  [ -f "$comment_file" ]
  grep -q "ERROR:" "$comment_file"
}

@test "valid run writes no comment file" {
  run uv run --locked "$VALIDATE" "$SCHEMA" "$VALID"
  [ "$status" -eq 0 ]
  ! grep -q "^comment-file=" "$GITHUB_OUTPUT"
}

@test "missing schema argument fails" {
  run uv run --locked "$VALIDATE" "" "$VALID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Schema file not found"* ]]
}

@test "missing file argument fails" {
  run uv run --locked "$VALIDATE" "$SCHEMA" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"YAML file not found"* ]]
}

@test "nonexistent schema file fails" {
  run uv run --locked "$VALIDATE" "/nonexistent/schema.json" "$VALID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Schema file not found"* ]]
}

@test "nonexistent YAML file fails" {
  run uv run --locked "$VALIDATE" "$SCHEMA" "/nonexistent/file.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"YAML file not found"* ]]
}

@test "run.sh wrapper validates a repo-relative file" {
  export GITHUB_ACTION_PATH="$ACTION_DIR"
  export GITHUB_WORKSPACE="$PROJECT_ROOT"
  export SCHEMA="validate-yaml/tests/fixtures/valid.schema.json"
  export FILE="validate-yaml/tests/fixtures/valid.yml"
  run bash "$ACTION_DIR/run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "run.sh wrapper fails with comment file on malformed YAML" {
  export GITHUB_ACTION_PATH="$ACTION_DIR"
  export GITHUB_WORKSPACE="$PROJECT_ROOT"
  export SCHEMA="validate-yaml/tests/fixtures/valid.schema.json"
  export FILE="validate-yaml/tests/fixtures/malformed.yml"
  run bash "$ACTION_DIR/run.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR:"* ]]
  grep -q "^comment-file=" "$GITHUB_OUTPUT"
  comment_file="$(grep "^comment-file=" "$GITHUB_OUTPUT" | sed 's/^comment-file=//')"
  [ -f "$comment_file" ]
  grep -q "ERROR:" "$comment_file"
}
