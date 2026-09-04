#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-required-check-docs.sh"

# The guard verifies all three reusable workflows in one run, so every test
# scaffolds the same baseline: three workflow files whose top-level job ids match
# the tokens after " / " in their README "Required status checks" text block.
# typescript-ci-checks deliberately defines an extra job (auto-fix) that is
# excluded from the required list, mirroring the real workflow.

write_workflow() {
  local name="$1"
  shift
  mkdir -p "$TEST_TEMP_DIR/workflows"
  {
    echo "name: $name"
    echo "on:"
    echo "  workflow_call:"
    echo "jobs:"
    for job in "$@"; do
      echo "  $job:"
    done
  } > "$TEST_TEMP_DIR/workflows/$name.yml"
}

write_readme() {
  cat > "$TEST_TEMP_DIR/README.md" <<'EOF'
### `ci-checks`

```text
c / alpha
c / beta
```

### `shell-ci-checks`

```text
s / gamma
s / delta
```

### `typescript-ci-checks`

```text
t / epsilon
t / zeta
```
EOF
}

setup_all_match() {
  write_workflow ci-checks alpha beta
  write_workflow shell-ci-checks gamma delta
  write_workflow typescript-ci-checks epsilon zeta auto-fix
  write_readme
}

run_guard() {
  run env \
    WORKFLOWS_DIR="$TEST_TEMP_DIR/workflows" \
    README_PATH="$TEST_TEMP_DIR/README.md" \
    bash "$SCRIPT"
}

@test "workflow job ids match README required checks -> success" {
  setup_all_match
  run_guard
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "README required-status-checks blocks match"
}

@test "workflow job missing from the README block -> failure naming the job" {
  setup_all_match
  # Add an extra job that the README block does not list.
  write_workflow ci-checks alpha beta extra
  run_guard
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ci-checks"
  echo "$output" | grep -q "extra"
  echo "$output" | grep -q "not listed as required checks"
}

@test "README token that is not a workflow job -> failure naming the token" {
  setup_all_match
  # Document a check the ci-checks.yml does not define.
  sed -i '' 's#^c / beta$#c / beta\nc / nope#' "$TEST_TEMP_DIR/README.md"
  run_guard
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ci-checks"
  echo "$output" | grep -q "nope"
  echo "$output" | grep -q "listed but not a workflow job"
}

@test "excluded job (auto-fix) must not be documented as a required check" {
  setup_all_match
  # The baseline already passes while auto-fix is a yml job but not in the block.
  run_guard
  [ "$status" -eq 0 ]
  # Adding auto-fix to the block must then fail as extra.
  sed -i '' 's#^t / zeta$#t / zeta\nt / auto-fix#' "$TEST_TEMP_DIR/README.md"
  run_guard
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "typescript-ci-checks"
  echo "$output" | grep -q "auto-fix"
}

@test "missing workflow file -> failure" {
  write_readme
  write_workflow ci-checks alpha beta
  write_workflow shell-ci-checks gamma delta
  run_guard
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "typescript-ci-checks.yml not found"
}

@test "missing README section -> failure listing its jobs as undocumented" {
  write_workflow ci-checks alpha beta
  write_workflow shell-ci-checks gamma delta
  write_workflow typescript-ci-checks epsilon zeta auto-fix
  # README without the typescript-ci-checks section.
  cat > "$TEST_TEMP_DIR/README.md" <<'EOF'
### `ci-checks`

```text
c / alpha
c / beta
```

### `shell-ci-checks`

```text
s / gamma
s / delta
```
EOF
  run_guard
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "typescript-ci-checks"
  echo "$output" | grep -q "epsilon"
  echo "$output" | grep -q "zeta"
}
