#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-workflows.sh"
BASH_BIN="$(command -v bash)"

# actionlint resolves a local `uses: ./...` through git, so every case that
# expects a real lint result needs a work tree around the fixture.
make_worktree_fixture() {
  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  git -C "$TEST_TEMP_DIR" init -q
}

run_verify() {
  run env WORKFLOW_ROOT="$TEST_TEMP_DIR/.github/workflows" bash "$SCRIPT"
}

@test "type-correct call -> success" {
  make_worktree_fixture
  cat > "$TEST_TEMP_DIR/.github/workflows/callee.yml" <<'EOF'
on:
  workflow_call:
    inputs:
      publish-comment:
        type: boolean
        default: true
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
  cat > "$TEST_TEMP_DIR/.github/workflows/caller.yml" <<'EOF'
on:
  push:
jobs:
  a:
    uses: ./.github/workflows/callee.yml
    with:
      publish-comment: false
EOF

  run_verify
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "pass actionlint"
}

# The defect this guard exists for: a boolean-like string assigned to a string
# input. GitHub fails the whole workflow file, so no job runs at all.
@test "bool-like string on a string input -> failure naming the input" {
  make_worktree_fixture
  cat > "$TEST_TEMP_DIR/.github/workflows/callee.yml" <<'EOF'
on:
  workflow_call:
    inputs:
      publish-comment:
        type: string
        default: 'true'
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
  cat > "$TEST_TEMP_DIR/.github/workflows/caller.yml" <<'EOF'
on:
  push:
jobs:
  a:
    uses: ./.github/workflows/callee.yml
    with:
      publish-comment: 'false'
EOF

  run_verify
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'input "publish-comment" is typed as string'
  echo "$output" | grep -q "startup_failure"
}

# Without a work tree actionlint skips local reusable workflows and exits 0.
# Reporting that as a pass would hide the very defect the guard exists for.
@test "not a git work tree -> failure, not a silent pass" {
  mkdir -p "$TEST_TEMP_DIR/wf"
  cat > "$TEST_TEMP_DIR/wf/caller.yml" <<'EOF'
on:
  push:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF

  run env WORKFLOW_ROOT="$TEST_TEMP_DIR/wf" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not inside a git work tree"
  ! echo "$output" | grep -q "pass actionlint"
}

@test "no workflow files -> failure" {
  mkdir -p "$TEST_TEMP_DIR/wf"
  git -C "$TEST_TEMP_DIR" init -q

  run env WORKFLOW_ROOT="$TEST_TEMP_DIR/wf" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "no workflow files found"
}

@test "missing workflow directory -> failure" {
  run env WORKFLOW_ROOT="$TEST_TEMP_DIR/absent" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "workflow directory not found"
}

# PATH carries dirname but not actionlint: the script resolves its own location
# before it reaches the check, so an empty PATH would fail on dirname instead.
@test "actionlint not on PATH -> failure with the install hint" {
  mkdir -p "$TEST_TEMP_DIR/bin" "$TEST_TEMP_DIR/wf"
  ln -s "$(command -v dirname)" "$TEST_TEMP_DIR/bin/dirname"

  run env PATH="$TEST_TEMP_DIR/bin" WORKFLOW_ROOT="$TEST_TEMP_DIR/wf" "$BASH_BIN" "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "actionlint is required but not found"
  echo "$output" | grep -q "make install-prereqs"
}
