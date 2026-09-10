#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/generate-mise-toml.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  NVMRC="$TEST_TEMP_DIR/.nvmrc"
  VERSIONS_MK="$TEST_TEMP_DIR/versions.mk"
  MISE_TOML="$TEST_TEMP_DIR/mise.toml"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

write_nvmrc() {
  printf '%s\n' "$1" > "$NVMRC"
}

write_versions_mk() {
  printf '%s\n' "$1" > "$VERSIONS_MK"
}

run_generator() {
  run env \
    NVMRC_PATH="$NVMRC" \
    VERSIONS_MK_PATH="$VERSIONS_MK" \
    MISE_TOML_PATH="$MISE_TOML" \
    bash "$SCRIPT" "$@"
}

# -- Write mode --

@test "writes mise.toml from .nvmrc and versions.mk" {
  write_nvmrc "24"
  write_versions_mk "BATS_VERSION := 1.14.0"

  run_generator
  [ "$status" -eq 0 ]
  grep -q '^node = "24"$' "$MISE_TOML"
  grep -q '^bats = "1.14.0"$' "$MISE_TOML"
}

@test "declares dev-only tools as constants for shellcheck, uv, and jq" {
  write_nvmrc "24"
  write_versions_mk "BATS_VERSION := 1.14.0"

  run_generator
  [ "$status" -eq 0 ]
  grep -q '^shellcheck = "' "$MISE_TOML"
  grep -q '^uv = "' "$MISE_TOML"
  grep -q '^jq = "' "$MISE_TOML"
}

@test "strips a leading v from .nvmrc" {
  write_nvmrc "v24"
  write_versions_mk "BATS_VERSION := 1.14.0"

  run_generator
  [ "$status" -eq 0 ]
  grep -q '^node = "24"$' "$MISE_TOML"
}

@test "output is deterministic across runs" {
  write_nvmrc "24"
  write_versions_mk "BATS_VERSION := 1.14.0"

  run_generator
  cp "$MISE_TOML" "$TEST_TEMP_DIR/first.toml"
  run_generator
  [ "$status" -eq 0 ]
  diff "$TEST_TEMP_DIR/first.toml" "$MISE_TOML"
}

# -- Check mode --

@test "check mode passes when mise.toml is in sync" {
  write_nvmrc "24"
  write_versions_mk "BATS_VERSION := 1.14.0"
  run_generator

  run_generator --check
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "in sync"
}

@test "check mode fails on drift" {
  write_nvmrc "24"
  write_versions_mk "BATS_VERSION := 1.14.0"
  run_generator
  printf '[tools]\nnode = "99"\n' > "$MISE_TOML"

  run_generator --check
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "out of sync"
}

@test "check mode fails when mise.toml is missing" {
  write_nvmrc "24"
  write_versions_mk "BATS_VERSION := 1.14.0"

  run_generator --check
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "mise.toml not found"
}

# -- Source errors --

@test "missing .nvmrc -> failure and no file written" {
  write_versions_mk "BATS_VERSION := 1.14.0"

  run_generator
  [ "$status" -ne 0 ]
  echo "$output" | grep -q ".nvmrc not found"
  [ ! -f "$MISE_TOML" ]
}

@test "empty .nvmrc -> failure" {
  write_nvmrc ""
  write_versions_mk "BATS_VERSION := 1.14.0"

  run_generator
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "is empty"
}

@test "missing versions.mk -> failure" {
  write_nvmrc "24"

  run_generator
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "versions.mk not found"
}

@test "missing BATS_VERSION -> failure and no file written" {
  write_nvmrc "24"
  write_versions_mk "OTHER_VERSION := 1.0.0"

  run_generator
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "BATS_VERSION not found"
  [ ! -f "$MISE_TOML" ]
}

@test "unknown argument -> failure" {
  write_nvmrc "24"
  write_versions_mk "BATS_VERSION := 1.14.0"

  run_generator --bogus
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "unknown argument"
}
