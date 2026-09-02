#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/validate-links/install.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  export GITHUB_PATH="$TEST_TEMP_DIR/github_path"
  export RUNNER_TOOL_CACHE="$TEST_TEMP_DIR/cache"
  export LYCHEE_VERSION="0.24.2"

  mkdir -p "$TEST_TEMP_DIR/bin"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"

  # curl writes the -o output file so later steps see the archive present.
  cat > "$TEST_TEMP_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" && -n "$arg" ]]; then
    : > "$arg"
  fi
  prev="$arg"
done
EOF
  chmod +x "$TEST_TEMP_DIR/bin/curl"

  # sha256sum -c always verifies OK.
  cat > "$TEST_TEMP_DIR/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/bin/sha256sum"

  # tar extracts a fake archive containing the target-named lychee binary.
  cat > "$TEST_TEMP_DIR/bin/tar" <<'EOF'
#!/usr/bin/env bash
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-C" && -n "$arg" ]]; then
    mkdir -p "$arg/lychee-x86_64-unknown-linux-gnu"
    printf '#!/usr/bin/env bash\n' > "$arg/lychee-x86_64-unknown-linux-gnu/lychee"
    chmod +x "$arg/lychee-x86_64-unknown-linux-gnu/lychee"
  fi
  prev="$arg"
done
EOF
  chmod +x "$TEST_TEMP_DIR/bin/tar"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

mock_uname() {
  local s="$1" m="$2"
  cat > "$TEST_TEMP_DIR/bin/uname" <<EOF
#!/usr/bin/env bash
case "\$1" in
  -s) echo "$s" ;;
  -m) echo "$m" ;;
esac
EOF
  chmod +x "$TEST_TEMP_DIR/bin/uname"
}

@test "default Linux x86_64 host: installs the pinned version and appends the bin dir to GITHUB_PATH" {
  mock_uname "Linux" "x86_64"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -Fq "$TEST_TEMP_DIR/cache/lychee/lychee-v0.24.2/lychee-x86_64-unknown-linux-gnu" "$TEST_TEMP_DIR/github_path"
}

@test "v-prefixed version is normalized to the lychee-v release tag" {
  mock_uname "Linux" "x86_64"
  run env LYCHEE_VERSION="v0.24.2" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -Fq "lychee-v0.24.2" "$TEST_TEMP_DIR/github_path"
}

@test "already lychee-prefixed version is accepted" {
  mock_uname "Linux" "x86_64"
  run env LYCHEE_VERSION="lychee-v0.24.2" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -Fq "lychee-v0.24.2" "$TEST_TEMP_DIR/github_path"
}

@test "LYCHEE_VERSION unset -> failure" {
  run env -u LYCHEE_VERSION bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "LYCHEE_VERSION is required"
}

@test "unsupported OS -> failure" {
  mock_uname "SunOS" "x86_64"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "unsupported OS 'SunOS'"
}

@test "unsupported architecture -> failure" {
  mock_uname "Linux" "sparc"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "unsupported architecture 'sparc'"
}

@test "missing lychee binary in the tarball -> failure" {
  mock_uname "Linux" "x86_64"
  # Override tar so the archive extracts without the lychee binary.
  cat > "$TEST_TEMP_DIR/bin/tar" <<'EOF'
#!/usr/bin/env bash
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-C" && -n "$arg" ]]; then
    mkdir -p "$arg/lychee-x86_64-unknown-linux-gnu"
  fi
  prev="$arg"
done
EOF
  chmod +x "$TEST_TEMP_DIR/bin/tar"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "lychee binary not found"
}
