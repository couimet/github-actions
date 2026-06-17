#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-versions.sh"

write_fixtures() {
  local nvmrc="$1" pnpm="$2"
  printf '%s\n' "$nvmrc" > "$TEST_TEMP_DIR/.nvmrc"
  cat > "$TEST_TEMP_DIR/package.json" <<EOF
{
  "packageManager": "pnpm@${pnpm}"
}
EOF
}

@test "exact node and pnpm match -> success" {
  write_fixtures "24.3.1" "9.1.0"
  run env \
    NVMRC_PATH="$TEST_TEMP_DIR/.nvmrc" \
    PACKAGE_JSON_PATH="$TEST_TEMP_DIR/package.json" \
    NODE_VERSION_OUTPUT="v24.3.1" \
    PNPM_VERSION_OUTPUT="9.1.0" \
    "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "node with patch suffix against major-only .nvmrc -> success" {
  write_fixtures "24" "9.1.0"
  run env \
    NVMRC_PATH="$TEST_TEMP_DIR/.nvmrc" \
    PACKAGE_JSON_PATH="$TEST_TEMP_DIR/package.json" \
    NODE_VERSION_OUTPUT="v24.3.1" \
    PNPM_VERSION_OUTPUT="9.1.0" \
    "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "node mismatch -> failure with error message" {
  write_fixtures "24" "9.1.0"
  run env \
    NVMRC_PATH="$TEST_TEMP_DIR/.nvmrc" \
    PACKAGE_JSON_PATH="$TEST_TEMP_DIR/package.json" \
    NODE_VERSION_OUTPUT="v22.0.0" \
    PNPM_VERSION_OUTPUT="9.1.0" \
    "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Node version mismatch"
}

@test "pnpm mismatch -> failure with error message" {
  write_fixtures "24.3.1" "9.1.0"
  run env \
    NVMRC_PATH="$TEST_TEMP_DIR/.nvmrc" \
    PACKAGE_JSON_PATH="$TEST_TEMP_DIR/package.json" \
    NODE_VERSION_OUTPUT="v24.3.1" \
    PNPM_VERSION_OUTPUT="8.0.0" \
    "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "pnpm version mismatch"
}

@test "leading v in .nvmrc is tolerated -> success" {
  write_fixtures "v24" "9.1.0"
  run env \
    NVMRC_PATH="$TEST_TEMP_DIR/.nvmrc" \
    PACKAGE_JSON_PATH="$TEST_TEMP_DIR/package.json" \
    NODE_VERSION_OUTPUT="24.0.0" \
    PNPM_VERSION_OUTPUT="9.1.0" \
    "$SCRIPT"
  [ "$status" -eq 0 ]
}
