#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/markdownlint/lint.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/markdownlint-cli2" <<'ENDOFSTUB'
#!/usr/bin/env bash
echo "markdownlint-cli2 args: $*"
exit 0
ENDOFSTUB
  chmod +x "$TEST_TEMP_DIR/bin/markdownlint-cli2"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"

  # cd into a temp dir so glob expansion is controlled.
  cd "$TEST_TEMP_DIR"
  touch fixture.md
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

@test "auto-discovery: omits --config when CONFIG is empty" {
  run env GLOBS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -Fqe "--config"
  echo "$output" | grep -q "markdownlint-cli2 args: \*.md$"
}

@test "explicit config: passes --config when CONFIG is set" {
  run env CONFIG=".markdownlint-cli2.jsonc" GLOBS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --config .markdownlint-cli2.jsonc *.md"
}

@test "multi-glob: splits GLOBS on whitespace into separate arguments" {
  mkdir -p "$TEST_TEMP_DIR/docs"
  touch "$TEST_TEMP_DIR/docs/readme.md"
  run env GLOBS="*.md docs/*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: *.md docs/*.md"
}

@test "GLOBS unset fails with required error" {
  run env bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "GLOBS is required"
}
