#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/request-coderabbit-full-review/request-coderabbit-full-review.sh"

# This action is not live self-tested in ci.yml: a live run posts a
# @coderabbitai comment that triggers a real CodeRabbit full review on this
# repo's PRs. Script logic is covered here by BATS instead.

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  # Fake gh: log its arguments to GH_LOG and print the comment id that real
  # gh would extract via --jq '.id'.
  GH_LOG="$TEST_TEMP_DIR/gh.log"
  export GH_LOG
  cat >"$TEST_TEMP_DIR/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
printf '42\n'
EOF
  chmod +x "$TEST_TEMP_DIR/gh"
  export PATH="$TEST_TEMP_DIR:$PATH"

  export GITHUB_OUTPUT
  GITHUB_OUTPUT="$(mktemp)"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
  rm -f "$GITHUB_OUTPUT"
}

# T1 — posts the review request comment and writes comment-id to GITHUB_OUTPUT
@test "posts review request comment and writes comment-id" {
  export REPO="my-org/my-repo"
  export PR_NUMBER=42
  export TRIGGER="base-changed-to-main"
  export METADATA='{"previous_base": "some-old-base"}'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "comment-id=42" "$GITHUB_OUTPUT"
  grep -q "repos/my-org/my-repo/issues/42/comments" "$GH_LOG"
  grep -q -- "--method POST" "$GH_LOG"
  grep -q '@coderabbitai full review' "$GH_LOG"
  grep -q 'base-changed-to-main' "$GH_LOG"
  grep -q '"previous_base"' "$GH_LOG"
  grep -q '"some-old-base"' "$GH_LOG"
}

# T2 — missing PR_NUMBER fails
@test "missing PR_NUMBER fails" {
  export REPO="my-org/my-repo"
  export PR_NUMBER=""
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# T3 — missing REPO fails
@test "missing REPO fails" {
  export REPO=""
  export PR_NUMBER=42
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# T4 — invalid METADATA JSON fails
@test "invalid METADATA JSON fails" {
  export REPO="my-org/my-repo"
  export PR_NUMBER=42
  export METADATA="{not valid json"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

# T5 — TRIGGER defaults to workflow when unset
@test "TRIGGER defaults to workflow when unset" {
  export REPO="my-org/my-repo"
  export PR_NUMBER=42
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"trigger"' "$GH_LOG"
  grep -q '"workflow"' "$GH_LOG"
}

# T6 — scalar METADATA fails with a clear error
@test "scalar METADATA fails" {
  export REPO="my-org/my-repo"
  export PR_NUMBER=42
  export METADATA='42'
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'METADATA must be a JSON object'
}

# T7 — array METADATA fails with a clear error
@test "array METADATA fails" {
  export REPO="my-org/my-repo"
  export PR_NUMBER=42
  export METADATA='["a","b"]'
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'METADATA must be a JSON object'
}
