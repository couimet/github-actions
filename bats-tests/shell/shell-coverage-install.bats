#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/shell-coverage/install-kcov.sh"

# The script builds kcov from a GitHub archive. The suite stubs curl, sudo, and
# cmake so no network, no root, and no compiler are needed, and builds the
# fixture tarball locally so KCOV_SHA256 can be a real digest of real bytes.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  STUB_LOG_DIR="$TEST_TEMP_DIR/logs"
  STUB_BIN_DIR="$TEST_TEMP_DIR/bin"
  export STUB_LOG_DIR STUB_BIN_DIR
  mkdir -p "$STUB_LOG_DIR" "$STUB_BIN_DIR"

  export KCOV_COMMIT="a39874f938ce13f7a65f253120d1ec946b349ffe"

  # One tarball, hashed once and copied by the stub, so the checksum the script
  # verifies is the checksum of the bytes it actually receives.
  STUB_TARBALL="$TEST_TEMP_DIR/kcov.tar.gz"
  export STUB_TARBALL
  build_fixture_tarball "$STUB_TARBALL"
  KCOV_SHA256="$(sha256_of "$STUB_TARBALL")"
  export KCOV_SHA256

  export KCOV_INSTALL_DIR="$TEST_TEMP_DIR/install"
  export GITHUB_PATH="$TEST_TEMP_DIR/github_path"

  stub sudo
  stub_curl
  stub_cmake

  # Pin PATH to the stub dir plus the system binaries the script and these
  # assertions need. A developer machine with kcov installed (brew, or the
  # upstream incubation) would otherwise satisfy the script's `command -v kcov`
  # check, short-circuit every install path, and turn these tests into passes
  # that assert nothing.
  export PATH="$STUB_BIN_DIR:/usr/bin:/bin"

  # Fail loudly rather than skip. A skip here would silently turn every install
  # path below into a no-op that still reports green.
  if command -v kcov >/dev/null 2>&1; then
    echo "kcov resolves to $(command -v kcov) on the pinned PATH; the suite cannot stub it" >&2
    return 1
  fi
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

build_fixture_tarball() {
  local target="$1" work
  work="$(mktemp -d)"
  mkdir -p "$work/kcov-${KCOV_COMMIT}"
  printf 'project(kcov)\n' > "$work/kcov-${KCOV_COMMIT}/CMakeLists.txt"
  tar -czf "$target" -C "$work" "kcov-${KCOV_COMMIT}"
  rm -rf "$work"
}

# Writes a stub onto PATH that logs its arguments.
stub() {
  local name="$1"
  cat > "$STUB_BIN_DIR/$name" << STUB
#!/usr/bin/env bash
echo "\$@" >> "\$STUB_LOG_DIR/${name}.log"
STUB
  chmod +x "$STUB_BIN_DIR/$name"
}

# curl -fsSL ... "$URL" -o "$out": copy the fixture tarball to the -o path.
stub_curl() {
  cat > "$STUB_BIN_DIR/curl" << 'STUB'
#!/usr/bin/env bash
echo "$@" >> "$STUB_LOG_DIR/curl.log"
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$out" ]] || exit 0
cp "$STUB_TARBALL" "$out"
STUB
  chmod +x "$STUB_BIN_DIR/curl"
}

# cmake records the configured install prefix, then materializes a fake kcov on
# --install so the script's post-install binary check passes.
stub_cmake() {
  cat > "$STUB_BIN_DIR/cmake" << 'STUB'
#!/usr/bin/env bash
echo "$@" >> "$STUB_LOG_DIR/cmake.log"
for arg in "$@"; do
  case "$arg" in
    -DCMAKE_INSTALL_PREFIX=*)
      printf '%s' "${arg#-DCMAKE_INSTALL_PREFIX=}" > "$STUB_LOG_DIR/prefix"
      ;;
  esac
done
if [[ "${1:-}" == "--install" ]]; then
  prefix="$(cat "$STUB_LOG_DIR/prefix")"
  mkdir -p "$prefix/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$prefix/bin/kcov"
  chmod +x "$prefix/bin/kcov"
fi
exit 0
STUB
  chmod +x "$STUB_BIN_DIR/cmake"
}

# --- Required inputs --------------------------------------------------------

@test "KCOV_COMMIT unset -> exits 1 with a clear error" {
  run env -u KCOV_COMMIT bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "KCOV_COMMIT is required" ]]
}

@test "KCOV_SHA256 unset -> exits 1 with a clear error" {
  run env -u KCOV_SHA256 bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "KCOV_SHA256 is required" ]]
}

# --- Short-circuit paths ----------------------------------------------------

@test "kcov already on PATH -> exits 0 without installing anything" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN_DIR/kcov"
  chmod +x "$STUB_BIN_DIR/kcov"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already on PATH" ]]
  [ ! -f "$STUB_LOG_DIR/sudo.log" ]
  [ ! -f "$STUB_LOG_DIR/curl.log" ]
}

# A cache hit skips the compile but must still write GITHUB_PATH, because the
# cache restores files and not the job's PATH.
@test "cached kcov -> skips the build, still appends the bin dir to GITHUB_PATH" {
  mkdir -p "$KCOV_INSTALL_DIR/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$KCOV_INSTALL_DIR/bin/kcov"
  chmod +x "$KCOV_INSTALL_DIR/bin/kcov"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Reusing cached kcov" ]]
  grep -qx "$KCOV_INSTALL_DIR/bin" "$GITHUB_PATH"
  [ ! -f "$STUB_LOG_DIR/curl.log" ]
  [ ! -f "$STUB_LOG_DIR/cmake.log" ]
}

# The restored binary is dynamically linked, so the packages cannot be gated on
# a cache miss or kcov exists and cannot start.
@test "cached kcov -> still installs the shared-library packages" {
  mkdir -p "$KCOV_INSTALL_DIR/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$KCOV_INSTALL_DIR/bin/kcov"
  chmod +x "$KCOV_INSTALL_DIR/bin/kcov"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "apt-get install" "$STUB_LOG_DIR/sudo.log"
  grep -q "libcurl4-openssl-dev" "$STUB_LOG_DIR/sudo.log"
}

# --- Happy path -------------------------------------------------------------

@test "cold build -> downloads, verifies, builds, installs, and exports PATH" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Installed kcov to" ]]
  grep -q "github.com/SimonKagstrom/kcov/archive/${KCOV_COMMIT}.tar.gz" "$STUB_LOG_DIR/curl.log"
  grep -q -- "-DCMAKE_INSTALL_PREFIX=$KCOV_INSTALL_DIR" "$STUB_LOG_DIR/cmake.log"
  [ -x "$KCOV_INSTALL_DIR/bin/kcov" ]
  grep -qx "$KCOV_INSTALL_DIR/bin" "$GITHUB_PATH"
}

@test "cold build -> installs the build dependencies including python3" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # python3 is required for src/bash-cloexec-library.cc; the build fails without it.
  grep -q "python3" "$STUB_LOG_DIR/sudo.log"
  grep -q "cmake" "$STUB_LOG_DIR/sudo.log"
  grep -q "libssl-dev" "$STUB_LOG_DIR/sudo.log"
}

@test "cold build -> with GITHUB_PATH unset, still exits 0" {
  run env -u GITHUB_PATH bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -x "$KCOV_INSTALL_DIR/bin/kcov" ]
}

# --- Checksum refusal -------------------------------------------------------

@test "checksum mismatch -> exits 1 without building" {
  run env KCOV_SHA256="$(printf '0%.0s' {1..64})" bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "checksum mismatch" ]]
  [[ "$output" =~ "Refusing to build from an unverified archive" ]]
  [ ! -f "$STUB_LOG_DIR/cmake.log" ]
  [ ! -x "$KCOV_INSTALL_DIR/bin/kcov" ]
}

# --- Install directory default ---------------------------------------------

@test "KCOV_INSTALL_DIR unset -> installs under RUNNER_TOOL_CACHE/kcov/<commit>" {
  run env -u KCOV_INSTALL_DIR RUNNER_TOOL_CACHE="$TEST_TEMP_DIR/toolcache" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -x "$TEST_TEMP_DIR/toolcache/kcov/$KCOV_COMMIT/bin/kcov" ]
  grep -qx "$TEST_TEMP_DIR/toolcache/kcov/$KCOV_COMMIT/bin" "$GITHUB_PATH"
}
