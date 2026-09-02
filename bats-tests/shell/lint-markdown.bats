#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/markdownlint/lint.sh"
FALLBACK="$PROJECT_ROOT/markdownlint/node_modules/@couimet/markdownlint-config/index.json"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/markdownlint-cli2" <<'ENDOFSTUB'
#!/usr/bin/env bash
echo "markdownlint-cli2 pwd: $(pwd)"
echo "markdownlint-cli2 args: $*"
# Capture the --config file and its path so tests can assert on contents and
# path; the script's EXIT trap removes temporary effective configs after the
# stub exits.
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--config" && $# -ge 2 ]]; then
    cp "$2" "$TEST_TEMP_DIR/captured-config.jsonc"
    printf '%s\n' "$2" > "$TEST_TEMP_DIR/captured-config-path.txt"
    break
  fi
  shift
done
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

# --- lint mode (default) ---

@test "zero-config fallback: applies bundled @couimet config when the repo has none" {
  run env PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --config $FALLBACK *.md"
}

@test "zero-config fallback: PATHS unset still applies the bundled config with . default" {
  run env bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --config $FALLBACK ."
}

@test "repo config authority: root .markdownlint.json suppresses the fallback" {
  touch "$TEST_TEMP_DIR/.markdownlint.json"
  run env PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -Fqe "--config"
  echo "$output" | grep -q "markdownlint-cli2 args: \*.md$"
}

@test "repo config authority: root .markdownlint-cli2.yaml (options file) suppresses the fallback" {
  touch "$TEST_TEMP_DIR/.markdownlint-cli2.yaml"
  run env PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -Fqe "--config"
  echo "$output" | grep -q "markdownlint-cli2 args: \*.md$"
}

@test "repo config authority: config nested under WORKING_DIRECTORY suppresses the fallback" {
  mkdir -p "$TEST_TEMP_DIR/sub"
  touch "$TEST_TEMP_DIR/sub/.markdownlint.json"
  run env PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -Fqe "--config"
  echo "$output" | grep -q "markdownlint-cli2 args: \*.md$"
}

@test "zero-config fallback: config in the parent of WORKING_DIRECTORY is ignored (cli2 search bound)" {
  mkdir -p "$TEST_TEMP_DIR/sub"
  touch "$TEST_TEMP_DIR/.markdownlint.json"
  run env PATHS="*.md" WORKING_DIRECTORY="sub" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "markdownlint-cli2 pwd: .*/sub$"
  echo "$output" | grep -Fq "markdownlint-cli2 args: --config $FALLBACK *.md"
}

@test "explicit config: passes --config when CONFIG is set" {
  run env CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --config .markdownlint-cli2.jsonc *.md"
}

@test "explicit config: CONFIG beats both a present repo config and the fallback" {
  touch "$TEST_TEMP_DIR/.markdownlint.json"
  run env CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --config .markdownlint-cli2.jsonc *.md"
  ! echo "$output" | grep -Fqe "$FALLBACK"
}

@test "multi-path: splits PATHS on whitespace into separate arguments" {
  mkdir -p "$TEST_TEMP_DIR/docs"
  touch "$TEST_TEMP_DIR/docs/readme.md"
  touch "$TEST_TEMP_DIR/.markdownlint.json"
  run env PATHS="*.md docs/*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: *.md docs/*.md"
}

@test "working directory: cds to WORKING_DIRECTORY before running" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/fixture.md"
  touch "$TEST_TEMP_DIR/subdir/.markdownlint.json"
  run env PATHS="*.md" WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "markdownlint-cli2 pwd: .*/subdir$"
  echo "$output" | grep -q "markdownlint-cli2 args: \*.md$"
}

# --- fix mode ---

@test "fix mode: zero-config fallback applies the bundled config" {
  run env MODE=fix PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --fix --config $FALLBACK *.md"
}

@test "fix mode: repo config suppresses the fallback and passes --fix" {
  touch "$TEST_TEMP_DIR/.markdownlint.json"
  run env MODE=fix PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -Fqe "--config"
  echo "$output" | grep -q "markdownlint-cli2 args: --fix \*.md$"
}

@test "fix mode: passes --config when CONFIG is set" {
  run env MODE=fix CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --fix --config .markdownlint-cli2.jsonc *.md"
}

@test "fix mode: splits PATHS on whitespace into separate arguments" {
  mkdir -p "$TEST_TEMP_DIR/docs"
  touch "$TEST_TEMP_DIR/docs/readme.md"
  touch "$TEST_TEMP_DIR/.markdownlint.json"
  run env MODE=fix PATHS="*.md docs/*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --fix *.md docs/*.md"
}

@test "fix mode: PATHS unset defaults to ." {
  touch "$TEST_TEMP_DIR/.markdownlint.json"
  run env MODE=fix bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "markdownlint-cli2 args: --fix \.$"
}

@test "fix mode: cds to WORKING_DIRECTORY before running" {
  mkdir -p "$TEST_TEMP_DIR/subdir"
  touch "$TEST_TEMP_DIR/subdir/fixture.md"
  touch "$TEST_TEMP_DIR/subdir/.markdownlint.json"
  run env MODE=fix PATHS="*.md" WORKING_DIRECTORY="subdir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "markdownlint-cli2 pwd: .*/subdir$"
  echo "$output" | grep -q "markdownlint-cli2 args: --fix \*.md$"
}

@test "rejects invalid MODE" {
  run env MODE=bogus bash "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ERROR: MODE must be 'check' or 'fix', got 'bogus'"
}

# --- fix mode MD060A registration ---

write_config() {
  local name="$1" content="$2"
  printf '%s\n' "$content" > "$TEST_TEMP_DIR/$name"
}

# Assert the --config path the stub captured is the unique temp file the script
# created next to the source: it sits in the working dir, ends with
# `.markdownlint-cli2.jsonc`, and is not the canonical source name.
assert_unique_temp_config() {
  local config_path
  config_path="$(cat "$TEST_TEMP_DIR/captured-config-path.txt")"
  [[ "$config_path" == ./*markdownlint-cli2.jsonc ]]
  [[ "$config_path" != ./.markdownlint-cli2.jsonc ]]
}

# Assert the EXIT trap removed every temp effective config, leaving only the
# config files the test itself created.
assert_no_temp_config_leftover() {
  [ -z "$(find "$TEST_TEMP_DIR" -maxdepth 1 -type f -name "*.markdownlint-cli2.jsonc" ! -name ".markdownlint-cli2.jsonc")" ]
}

@test "fix mode: injects MD060A into the effective config next to the source" {
  write_config ".markdownlint-cli2.jsonc" '{ "config": { "extends": "@couimet/markdownlint-config" } }'
  run env MODE=fix CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --fix --config"
  assert_unique_temp_config
  [ "$(jq -r '.config.extends' "$TEST_TEMP_DIR/captured-config.jsonc")" = "@couimet/markdownlint-config" ]
  [ "$(jq -r '.customRules[0]' "$TEST_TEMP_DIR/captured-config.jsonc")" = "markdownlint-rule-force-align-table-columns" ]
  assert_no_temp_config_leftover
}

@test "fix mode: auto-discovers the config and injects MD060A" {
  write_config ".markdownlint-cli2.jsonc" '{ "config": {} }'
  run env MODE=fix PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --fix --config"
  assert_unique_temp_config
  [ "$(jq -r '.customRules[0]' "$TEST_TEMP_DIR/captured-config.jsonc")" = "markdownlint-rule-force-align-table-columns" ]
}

@test "fix mode: does not duplicate an already-registered rule" {
  write_config ".markdownlint-cli2.jsonc" '{ "customRules": ["markdownlint-rule-force-align-table-columns"], "config": {} }'
  run env MODE=fix CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq '.customRules | length' "$TEST_TEMP_DIR/captured-config.jsonc")" = "1" ]
}

@test "fix mode: preserves existing custom rules and appends MD060A" {
  write_config ".markdownlint-cli2.jsonc" '{ "customRules": ["some-other-rule"], "config": {} }'
  run env MODE=fix CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.customRules[0]' "$TEST_TEMP_DIR/captured-config.jsonc")" = "some-other-rule" ]
  [ "$(jq -r '.customRules[1]' "$TEST_TEMP_DIR/captured-config.jsonc")" = "markdownlint-rule-force-align-table-columns" ]
}

@test "fix mode: wraps a .markdownlint.json config file into an options file" {
  write_config ".markdownlint.json" '{ "MD013": false }'
  run env MODE=fix CONFIG=".markdownlint.json" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --fix --config"
  assert_unique_temp_config
  [ "$(jq -r '.config.MD013' "$TEST_TEMP_DIR/captured-config.jsonc")" = "false" ]
  [ "$(jq -r '.customRules[0]' "$TEST_TEMP_DIR/captured-config.jsonc")" = "markdownlint-rule-force-align-table-columns" ]
}

@test "fix mode: parses JSONC configs with comments and trailing commas" {
  write_config ".markdownlint-cli2.jsonc" $'{\n  // comment\n  "config": { "MD013": false, },\n}'
  run env MODE=fix CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.config.MD013' "$TEST_TEMP_DIR/captured-config.jsonc")" = "false" ]
}

@test "fix mode: removes the temporary config on exit" {
  write_config ".markdownlint-cli2.jsonc" '{ "config": {} }'
  run env MODE=fix CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  assert_no_temp_config_leftover
}

@test "fix mode: passes JS-module configs through without injection" {
  write_config ".markdownlint-cli2.cjs" 'module.exports = { config: {} };'
  run env MODE=fix CONFIG=".markdownlint-cli2.cjs" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --fix --config .markdownlint-cli2.cjs *.md"
  assert_no_temp_config_leftover
}

@test "check mode: leaves the config untouched (no MD060A injection)" {
  write_config ".markdownlint-cli2.jsonc" '{ "config": { "extends": "@couimet/markdownlint-config" } }'
  run env CONFIG=".markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "markdownlint-cli2 args: --config .markdownlint-cli2.jsonc *.md"
  assert_no_temp_config_leftover
  [ ! -e "$TEST_TEMP_DIR/captured-config.jsonc" ] || ! grep -Fq "markdownlint-rule-force-align-table-columns" "$TEST_TEMP_DIR/captured-config.jsonc"
}

@test "check mode auto-discovery: omits --config and does not inject" {
  write_config ".markdownlint-cli2.jsonc" '{ "config": {} }'
  run env PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "markdownlint-cli2 args: \*.md$"
  assert_no_temp_config_leftover
}

@test "fix mode: preserves a consumer config named tmp.markdownlint-cli2.jsonc" {
  write_config "tmp.markdownlint-cli2.jsonc" '{ "config": { "MD013": false } }'
  run env MODE=fix CONFIG="tmp.markdownlint-cli2.jsonc" PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # The temp file is unique, so the CONFIG-selected file is never overwritten
  # or removed: it still exists with its original content after the run.
  [ -f "$TEST_TEMP_DIR/tmp.markdownlint-cli2.jsonc" ]
  [ "$(jq -r '.config.MD013' "$TEST_TEMP_DIR/tmp.markdownlint-cli2.jsonc")" = "false" ]
  [ "$(jq -r '.customRules' "$TEST_TEMP_DIR/tmp.markdownlint-cli2.jsonc")" = "null" ]
}
