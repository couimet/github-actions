#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/validate-links/report-private.sh"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  export GITHUB_OUTPUT="$TEST_TEMP_DIR/github_output"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Path recorded in GITHUB_OUTPUT when the scan found excluded private targets.
comment_file() {
  sed -n 's/^comment-file=//p' "$TEST_TEMP_DIR/github_output" 2>/dev/null | tail -1
}

@test "no private links: exits 0 with no comment output" {
  printf 'See https://example.com/ and https://8.8.8.8/.\n' > fixture.md
  : > "$TEST_TEMP_DIR/github_output"
  run env PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no links to private"
  [ ! -s "$TEST_TEMP_DIR/github_output" ]
}

@test "reports each private class, dedupes, and skips public hosts" {
  cat > fixture.md <<'EOF'
Public https://example.com/ and https://172.32.0.1/ and https://8.8.8.8/.
Loopback http://127.0.0.1:8080/a and http://127.0.0.1:8080/a again.
RFC1918 http://10.1.2.3/x and http://172.16.0.5/ and http://192.168.1.10/y.
Link-local http://169.254.1.1/ and http://[fe80::1%25eth0]/.
Loopback v6 http://[::1]:3000/. ULA http://[fd12::1]/.
EOF
  run env PATHS="*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local file
  file="$(comment_file)"
  [ -n "$file" ]
  grep -Fq -- '- `http://127.0.0.1:8080/a`' "$file"
  grep -Fq -- '- `http://10.1.2.3/x`' "$file"
  grep -Fq -- '- `http://172.16.0.5/`' "$file"
  grep -Fq -- '- `http://192.168.1.10/y`' "$file"
  grep -Fq -- '- `http://169.254.1.1/`' "$file"
  grep -Fq -- '- `http://[fe80::1%25eth0]/`' "$file"
  grep -Fq -- '- `http://[::1]:3000/`' "$file"
  grep -Fq -- '- `http://[fd12::1]/`' "$file"
  # The repeated loopback URL is listed once.
  [ "$(grep -c -- '- `http://127.0.0.1:8080/a`' "$file")" -eq 1 ]
  # Public hosts are never reported.
  ! grep -Fq 'example.com' "$file"
  ! grep -Fq '172.32.0.1' "$file"
  ! grep -Fq '8.8.8.8' "$file"
}

@test "working directory: scans files under WORKING_DIRECTORY" {
  mkdir -p "$TEST_TEMP_DIR/sub"
  printf 'http://127.0.0.1:5000/\n' > "$TEST_TEMP_DIR/sub/doc.md"
  run env PATHS="*.md" WORKING_DIRECTORY="sub" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local file
  file="$(comment_file)"
  [ -n "$file" ]
  grep -Fq -- '- `http://127.0.0.1:5000/`' "$file"
}

@test "includes hidden directories and excludes node_modules" {
  mkdir -p .github docs node_modules/pkg
  printf 'http://10.0.0.1/ hidden\n' > .github/a.md
  printf 'http://10.0.0.2/ docs\n' > docs/b.md
  printf 'http://10.0.0.3/ vendored\n' > node_modules/pkg/c.md
  run env PATHS="**/*.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local file
  file="$(comment_file)"
  [ -n "$file" ]
  grep -Fq -- '- `http://10.0.0.1/`' "$file"
  grep -Fq -- '- `http://10.0.0.2/`' "$file"
  ! grep -Fq -- '10.0.0.3' "$file"
}
