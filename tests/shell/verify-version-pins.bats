#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-version-pins.sh"

write_versions_mk() {
  printf '%s\n' "$1" > "$TEST_TEMP_DIR/versions.mk"
}

write_action_yml() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$TEST_TEMP_DIR/$path")"
  printf '%s\n' "$content" > "$TEST_TEMP_DIR/$path"
}

@test "all pins match -> success" {
  write_versions_mk "PRETTIER_VERSION := 3.8.4"
  write_action_yml "prettier/action.yml" "inputs:
  prettier-version:
    default: '3.8.4'"

  run env \
    VERSIONS_MK_PATH="$TEST_TEMP_DIR/versions.mk" \
    ACTION_ROOT="$TEST_TEMP_DIR" \
    CHECKS="PRETTIER_VERSION prettier prettier-version" \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "version drift -> failure with error message" {
  write_versions_mk "PRETTIER_VERSION := 9.9.9"
  write_action_yml "prettier/action.yml" "inputs:
  prettier-version:
    default: '3.8.4'"

  run env \
    VERSIONS_MK_PATH="$TEST_TEMP_DIR/versions.mk" \
    ACTION_ROOT="$TEST_TEMP_DIR" \
    CHECKS="PRETTIER_VERSION prettier prettier-version" \
    bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Version drift"
}

@test "variable missing from versions.mk -> failure" {
  write_versions_mk "OTHER_VERSION := 1.0.0"
  write_action_yml "prettier/action.yml" "inputs:
  prettier-version:
    default: '3.8.4'"

  run env \
    VERSIONS_MK_PATH="$TEST_TEMP_DIR/versions.mk" \
    ACTION_ROOT="$TEST_TEMP_DIR" \
    CHECKS="PRETTIER_VERSION prettier prettier-version" \
    bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not found"
}

@test "missing versions.mk -> failure" {
  run env VERSIONS_MK_PATH="/nonexistent/versions.mk" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "versions.mk not found"
}

@test "missing action.yml -> failure" {
  write_versions_mk "PRETTIER_VERSION := 3.8.4"

  run env \
    VERSIONS_MK_PATH="$TEST_TEMP_DIR/versions.mk" \
    ACTION_ROOT="$TEST_TEMP_DIR" \
    CHECKS="PRETTIER_VERSION prettier prettier-version" \
    bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Action file not found"
}
