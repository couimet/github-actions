#!/usr/bin/env bats

load test_helper

ACTION_DIR="$PROJECT_ROOT/validate-yaml"
FIXTURES="$ACTION_DIR/tests/fixtures"
VALIDATE="$ACTION_DIR/validate.sh"
SCHEMA="$FIXTURES/valid.schema.json"
VALID="$FIXTURES/valid.yml"
INVALID="$FIXTURES/invalid-missing-context.yml"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  cd "$ACTION_DIR"
  uv sync --locked --quiet
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
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
