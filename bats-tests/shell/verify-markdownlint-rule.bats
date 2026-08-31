#!/usr/bin/env bats

load test_helper

INJECTOR="$PROJECT_ROOT/markdownlint/inject-rule.cjs"
LINT_SH="$PROJECT_ROOT/markdownlint/lint.sh"
PACKAGE_JSON="$PROJECT_ROOT/markdownlint/package.json"

RULE="markdownlint-rule-force-align-table-columns"

# The injector hardcodes the rule it registers. If the rule ever drops out of
# markdownlint/package.json, the injector prints SKIP and fix-mode table
# auto-alignment silently stops — so both files must reference the same name.
@test "injector rule name matches the package.json devDependency" {
  grep -Fq "$RULE" "$INJECTOR"
  grep -Fq "\"$RULE\"" "$PACKAGE_JSON"
}

@test "lint.sh drives the injector in fix mode" {
  grep -Fq "inject-rule.cjs" "$LINT_SH"
  grep -Fq "tmp.markdownlint-cli2.jsonc" "$LINT_SH"
}
