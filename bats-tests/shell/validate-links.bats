#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/validate-links/run.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/lychee" <<'ENDOFSTUB'
#!/usr/bin/env bash
echo "lychee pwd: $(pwd)"
echo "lychee args: $*"
exit 0
ENDOFSTUB
  chmod +x "$TEST_TEMP_DIR/bin/lychee"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"

  # cd into a temp dir so glob expansion is controlled.
  cd "$TEST_TEMP_DIR"
  touch fixture.md
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

@test "always passes hidden, exclude-all-private, exclude-path and no-progress flags" {
  run env PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq -- "lychee args: --hidden --exclude-all-private --exclude-path node_modules --no-progress *.md"
}

@test "multi-path: splits PATHS on whitespace into separate arguments" {
  mkdir -p "$TEST_TEMP_DIR/docs"
  touch "$TEST_TEMP_DIR/docs/readme.md"
  run env PATHS="*.md docs/*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq -- "lychee args: --hidden --exclude-all-private --exclude-path node_modules --no-progress *.md docs/*.md"
}

@test "PATHS unset: defaults to **/*.md" {
  run env bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq -- "lychee args: --hidden --exclude-all-private --exclude-path node_modules --no-progress **/*.md"
}

@test "working directory: cds to WORKING_DIRECTORY before running" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/fixture.md"
  run env PATHS="*.md" WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lychee pwd: .*/subdir$"
  echo "$output" | grep -Fq -- "lychee args: --hidden --exclude-all-private --exclude-path node_modules --no-progress *.md"
}
