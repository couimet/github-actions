#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/verify-action-shas.sh"

setup() {
  # test_helper's setup is overridden; replicate its temp-dir creation.
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  # Create a mock gh CLI that succeeds only for SHAs listed in
  # $VALID_SHAS_FILE (one per line). Any other SHA exits 1.
  cat > "$TEST_TEMP_DIR/gh" <<'SCRIPT'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" =~ ^repos/.*/commits/([0-9a-f]{40})$ ]]; then
    sha="${BASH_REMATCH[1]}"
    break
  fi
done
if [[ -n "${sha:-}" ]] && [[ -f "${VALID_SHAS_FILE:-}" ]] && grep -qxF "$sha" "${VALID_SHAS_FILE:-}" 2>/dev/null; then
  echo "{\"sha\":\"$sha\"}"
  exit 0
fi
echo "{\"message\":\"Not Found\",\"documentation_url\":\"https://docs.github.com/rest\"}" >&2
exit 1
SCRIPT
  chmod +x "$TEST_TEMP_DIR/gh"

  # Default: empty valid-shas file (all SHAs are missing)
  touch "$TEST_TEMP_DIR/valid-shas.txt"

  mkdir -p "$TEST_TEMP_DIR/test-action"
}

# Helper: run the script with the mock gh on PATH and ACTION_ROOT in the temp dir.
run_script() {
  run bash -c "
    cd '$TEST_TEMP_DIR' && \
    PATH='$TEST_TEMP_DIR:$PATH' \
    VALID_SHAS_FILE='$TEST_TEMP_DIR/valid-shas.txt' \
    ACTION_ROOT='$TEST_TEMP_DIR' \
    bash '$SCRIPT'
  "
}

SHA1="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
SHA3="cccccccccccccccccccccccccccccccccccccccc"

# sha256 digest: SHA1 is 40 hex chars, so 24 more make the required 64.
DIGEST="sha256:${SHA1}aaaaaaaaaaaaaaaaaaaaaaaa"

# --- tests ---

@test "all SHAs valid -> success" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"
  echo "$SHA2" >> "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    - uses: owner2/repo2@${SHA2}
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 2 pinned SHA(s) verified"
}

@test "one SHA missing -> failure with error message" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    - uses: owner/repo@${SHA2}
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "MISSING"
  echo "$output" | grep -q "::error::SHA ${SHA2} not found"
}

@test "mixed valid and invalid -> failure" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    - uses: owner/repo@${SHA2}
EOF

  run_script
  [ "$status" -ne 0 ]
  # Only one MISSING line
  [ "$(echo "$output" | grep -c 'MISSING')" -eq 1 ]
  echo "$output" | grep -q "OK"
}

@test "no pinned SHAs -> success" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: ./local-action
    - uses: couimet/github-actions/publish-pr-comment@main
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 0 pinned SHA(s) verified"
}

@test "gh CLI not available -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
EOF

  mkdir -p "$TEST_TEMP_DIR/no-gh-bin"
  for cmd in bash dirname find sort sed grep; do
    ln -s "$(command -v "$cmd")" "$TEST_TEMP_DIR/no-gh-bin/$cmd"
  done
  run bash -c "
    cd '$TEST_TEMP_DIR' && \
    PATH='$TEST_TEMP_DIR/no-gh-bin' \
    ACTION_ROOT='$TEST_TEMP_DIR' \
    bash '$SCRIPT'
  "
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "gh CLI is required"
}

@test "quoted uses: values are parsed correctly" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"
  echo "$SHA2" >> "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: "owner/repo@${SHA1}"
    - uses: 'owner2/repo2@${SHA2}'
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 2 pinned SHA(s) verified"
}

@test "indented uses: under a step name is discovered" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - name: Do the thing
      uses: owner/repo@${SHA1}
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 1 pinned SHA(s) verified"
}

@test "missing SHA on an indented uses: line -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - name: Do the thing
      uses: owner/repo@${SHA2}
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "::error::SHA ${SHA2} not found"
}

@test "commented uses: lines are ignored" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    # - uses: owner/repo@${SHA2}
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 1 pinned SHA(s) verified"
}

@test "multiple missing SHAs reports correct count" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    - uses: owner/repo@${SHA2}
    - uses: owner/repo@${SHA3}
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "::error::2 pinned SHA(s) are missing"
}

@test "discovers deeply nested action.yml files" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  mkdir -p "$TEST_TEMP_DIR/a/b/c"
  cat > "$TEST_TEMP_DIR/a/b/c/action.yml" <<EOF
name: Deep
description: Deeply nested action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 1 pinned SHA(s) verified"
}

# --- ref policy (CI001 / CI002) ---

@test "third-party branch ref -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@main
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references owner/repo@main"
  echo "$output" | grep -q "Pin third-party actions to a full 40-character commit SHA"
}

@test "third-party tag ref -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@v4
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references owner/repo@v4"
  echo "$output" | grep -q "Pin third-party actions to a full 40-character commit SHA"
}

@test "first-party SHA pin -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: couimet/github-actions/publish-pr-comment@${SHA1}
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Internal actions must use @main"
}

@test "first-party @main ref -> success" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<EOF
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@${SHA1}
    - uses: couimet/github-actions/publish-pr-comment@main
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 1 pinned SHA(s) verified"
}

@test "workflow with a floating third-party ref -> failure" {
  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  cat > "$TEST_TEMP_DIR/.github/workflows/ci.yml" <<'EOF'
name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references actions/checkout@v4"
}

@test "workflow with a pinned SHA is verified, local paths skipped" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  cat > "$TEST_TEMP_DIR/.github/workflows/ci.yml" <<EOF
name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@${SHA1}
      - uses: ./setup-mise
      - uses: ./.github/workflows/reusable.yml
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 1 pinned SHA(s) verified"
}

@test "action.yml and workflow violations are both reported" {
  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  cat > "$TEST_TEMP_DIR/.github/workflows/ci.yml" <<'EOF'
name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/cache@v4
EOF

  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: owner/repo@main
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references owner/repo@main"
  echo "$output" | grep -q "references actions/cache@v4"
  echo "$output" | grep -q "::error::2 uses: reference(s) violate the pinning rules"
}

# --- Docker ref policy ---

@test "docker image tag ref -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: docker://alpine:3.18
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references docker://alpine:3.18"
  echo "$output" | grep -q "Pin Docker images by digest"
}

@test "docker image with no tag -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: docker://alpine
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references docker://alpine"
  echo "$output" | grep -q "Pin Docker images by digest"
}

@test "quoted docker image tag -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: "docker://alpine:3.18"
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "references docker://alpine:3.18"
  echo "$output" | grep -q "Pin Docker images by digest"
}

@test "docker image with a truncated digest -> failure" {
  cat > "$TEST_TEMP_DIR/test-action/action.yml" <<'EOF'
name: Test
description: Test action
runs:
  using: composite
  steps:
    - uses: docker://ghcr.io/owner/img@sha256:abc123
EOF

  run_script
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Pin Docker images by digest"
}

@test "digest-pinned docker image -> accepted and reported as unverified" {
  echo "$SHA1" > "$TEST_TEMP_DIR/valid-shas.txt"

  mkdir -p "$TEST_TEMP_DIR/.github/workflows"
  cat > "$TEST_TEMP_DIR/.github/workflows/ci.yml" <<EOF
name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@${SHA1}
      - uses: docker://ghcr.io/owner/img@${DIGEST}
EOF

  run_script
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "All 1 pinned SHA(s) verified"
  echo "$output" | grep -q "1 Docker image digest(s) accepted without remote verification"
}
