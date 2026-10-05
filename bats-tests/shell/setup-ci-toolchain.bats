#!/usr/bin/env bats

load test_helper

SCRIPT="$PROJECT_ROOT/scripts/setup-ci-toolchain.sh"

# The script reads HOME for the directory mise installs into, so every test
# points HOME at the temp dir. A test that let the real HOME through would
# install into the developer's own ~/.local/bin.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  FAKE_HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$FAKE_HOME" "$TEST_TEMP_DIR/root" "$TEST_TEMP_DIR/tools"

  export FAKE_HOME

  # The tests decide which commands exist, so the PATH below holds this
  # directory plus the stubs and nothing else. An inherited PATH would carry the
  # developer's own mise, curl, and actionlint, and every absence a test creates
  # would still resolve. The symlinks name the commands the script and its
  # stubs call.
  mkdir -p "$TEST_TEMP_DIR/sys-bin"
  local cmd
  for cmd in bash dirname awk cat cp chmod mkdir sh; do
    ln -s "$(command -v "$cmd")" "$TEST_TEMP_DIR/sys-bin/$cmd"
  done

  # Two tools, so a test can make one resolve and the other not.
  cat > "$TEST_TEMP_DIR/root/mise.toml" <<'TOML'
[tools]
uv = "1.0.0"
actionlint = "1.0.0"
TOML

  # The directories `mise bin-paths` reports, and the tool stubs they hold.
  # Those directories reach PATH only through the script, which is the wiring
  # the resolution checks below depend on.
  MISE_BIN_PATHS_FILE="$TEST_TEMP_DIR/bin-paths.txt"
  export MISE_BIN_PATHS_FILE
  printf '%s\n' "$TEST_TEMP_DIR/tools" > "$MISE_BIN_PATHS_FILE"

  local tool
  for tool in uv actionlint; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TEMP_DIR/tools/$tool"
    chmod +x "$TEST_TEMP_DIR/tools/$tool"
  done

  # Each stub sits in a directory of its own, so a test removes one command
  # from PATH without removing the others.
  mkdir -p "$TEST_TEMP_DIR/mise-bin" "$TEST_TEMP_DIR/curl-bin" "$TEST_TEMP_DIR/tool-bin"

  cat > "$TEST_TEMP_DIR/mise-bin/mise" <<'MISE'
#!/usr/bin/env bash
case "${1:-}" in
  install) exit "${MISE_INSTALL_STATUS:-0}" ;;
  bin-paths)
    if [[ "${MISE_BIN_PATHS_MISSING:-0}" == "1" ]]; then exit 1; fi
    cat "$MISE_BIN_PATHS_FILE"
    ;;
  *) exit 0 ;;
esac
MISE
  chmod +x "$TEST_TEMP_DIR/mise-bin/mise"

  # A curl that emits an installer which copies the mise stub into the fake
  # HOME, standing in for the release the real installer downloads.
  FAKE_MISE="$TEST_TEMP_DIR/mise-bin/mise"
  export FAKE_MISE

  cat > "$TEST_TEMP_DIR/installer.sh" <<'INSTALLER'
mkdir -p "$HOME/.local/bin"
cp "$FAKE_MISE" "$HOME/.local/bin/mise"
chmod +x "$HOME/.local/bin/mise"
INSTALLER

  cat > "$TEST_TEMP_DIR/curl-bin/curl" <<'CURL'
#!/usr/bin/env bash
cat "$FAKE_INSTALLER"
CURL
  chmod +x "$TEST_TEMP_DIR/curl-bin/curl"

  # An npm that records its call rather than installing anything.
  NPM_CALLS="$TEST_TEMP_DIR/npm-calls.txt"
  export NPM_CALLS

  cat > "$TEST_TEMP_DIR/tool-bin/npm" <<'NPM'
#!/usr/bin/env bash
echo "$*" >> "$NPM_CALLS"
NPM
  chmod +x "$TEST_TEMP_DIR/tool-bin/npm"

  GITHUB_PATH_FILE="$TEST_TEMP_DIR/github-path.txt"
  export GITHUB_PATH_FILE
  : > "$GITHUB_PATH_FILE"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}

# Run the script against the fixture. DROP_MISE, DROP_CURL, and
# DROP_GITHUB_PATH remove one input each, so a test can pin the branch that
# handles its absence.
run_script() {
  local prefix="$TEST_TEMP_DIR/tool-bin"
  if [[ "${DROP_CURL:-0}" != "1" ]]; then
    prefix="$TEST_TEMP_DIR/curl-bin:$prefix"
  fi
  if [[ "${DROP_MISE:-0}" != "1" ]]; then
    prefix="$TEST_TEMP_DIR/mise-bin:$prefix"
  fi
  prefix="$prefix:$TEST_TEMP_DIR/sys-bin"

  if [[ "${DROP_GITHUB_PATH:-0}" == "1" ]]; then
    run env \
      HOME="$FAKE_HOME" \
      PATH="$prefix" \
      TOOLCHAIN_ROOT="$TEST_TEMP_DIR/root" \
      MISE_BIN_PATHS_FILE="$MISE_BIN_PATHS_FILE" \
      MISE_INSTALL_STATUS="${MISE_INSTALL_STATUS:-0}" \
      MISE_BIN_PATHS_MISSING="${MISE_BIN_PATHS_MISSING:-0}" \
      FAKE_MISE="$FAKE_MISE" \
      FAKE_INSTALLER="${FAKE_INSTALLER:-$TEST_TEMP_DIR/installer.sh}" \
      NPM_CALLS="$NPM_CALLS" \
      bash "$SCRIPT"
  else
    run env \
      HOME="$FAKE_HOME" \
      PATH="$prefix" \
      TOOLCHAIN_ROOT="$TEST_TEMP_DIR/root" \
      GITHUB_PATH="$GITHUB_PATH_FILE" \
      MISE_BIN_PATHS_FILE="$MISE_BIN_PATHS_FILE" \
      MISE_INSTALL_STATUS="${MISE_INSTALL_STATUS:-0}" \
      MISE_BIN_PATHS_MISSING="${MISE_BIN_PATHS_MISSING:-0}" \
      FAKE_MISE="$FAKE_MISE" \
      FAKE_INSTALLER="${FAKE_INSTALLER:-$TEST_TEMP_DIR/installer.sh}" \
      NPM_CALLS="$NPM_CALLS" \
      bash "$SCRIPT"
  fi
}

# --- The tools mise.toml pins -----------------------------------------------

@test "every pinned tool resolves -> success, and the tool directory reaches GITHUB_PATH" {
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 pinned tool(s) resolve on PATH."* ]]
  # A workflow step runs outside this process, so PATH alone is not enough.
  grep -qxF "$TEST_TEMP_DIR/tools" "$GITHUB_PATH_FILE"
}

# Without a GITHUB_PATH the script still provisions and checks; the file is the
# workflow's channel, not the script's dependency.
@test "no GITHUB_PATH -> success" {
  DROP_GITHUB_PATH=1 run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 pinned tool(s) resolve on PATH."* ]]
}

# The tool list is read from mise.toml. A file that declares none would pass the
# loop above while checking nothing, which is the false pass to refuse.
@test "mise.toml declares no tool -> failure" {
  printf '[tools]\n' > "$TEST_TEMP_DIR/root/mise.toml"

  run_script
  [ "$status" -eq 1 ]
  [[ "$output" == *"declares no tool, so this script checked nothing"* ]]
}

@test "no mise.toml -> failure naming the expected path" {
  rm "$TEST_TEMP_DIR/root/mise.toml"

  run_script
  [ "$status" -eq 1 ]
  [[ "$output" == *"no mise.toml at '${TEST_TEMP_DIR}/root/mise.toml'"* ]]
}

@test "a pinned tool does not resolve -> failure naming it" {
  rm "$TEST_TEMP_DIR/tools/actionlint"

  run_script
  [ "$status" -eq 1 ]
  [[ "$output" == *"do not resolve on PATH: actionlint."* ]]
}

@test "mise bin-paths fails -> failure rather than an unchecked PATH" {
  MISE_BIN_PATHS_MISSING=1 run_script
  [ "$status" -eq 1 ]
  [[ "$output" == *"'mise bin-paths' failed"* ]]
}

# --- Getting mise onto the runner -------------------------------------------

@test "mise absent -> the installer provisions it, then the tools resolve" {
  DROP_MISE=1 run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise is absent; installing it."* ]]
  [ -x "$FAKE_HOME/.local/bin/mise" ]
  [[ "$output" == *"2 pinned tool(s) resolve on PATH."* ]]
}

@test "mise absent and curl absent -> failure naming the install route" {
  DROP_MISE=1 DROP_CURL=1 run_script
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl is not installed"* ]]
}

# An installer that exits 0 without installing anything is the silent case: the
# script must not read the next command's failure as a missing tool.
@test "the installer leaves mise off PATH -> failure naming the directory" {
  : > "$TEST_TEMP_DIR/noop-installer.sh"

  DROP_MISE=1 FAKE_INSTALLER="$TEST_TEMP_DIR/noop-installer.sh" run_script
  [ "$status" -eq 1 ]
  [[ "$output" == *"still does not resolve on PATH"* ]]
}

# --- The markdownlint dependency install ------------------------------------

# The markdownlint suite reads the bundled fallback config out of the action's
# node_modules, so the install must happen before the suite runs.
@test "markdownlint node_modules absent -> installs the dependencies" {
  mkdir -p "$TEST_TEMP_DIR/root/markdownlint"

  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"installing the markdownlint action dependencies"* ]]
  grep -q '^ci ' "$NPM_CALLS"
}

# `make lint-md` treats the directory as its own build marker, so the script
# skips the install the same way rather than paying for it on every run.
@test "markdownlint node_modules present -> skips the install" {
  mkdir -p "$TEST_TEMP_DIR/root/markdownlint/node_modules"

  run_script
  [ "$status" -eq 0 ]
  [[ "$output" != *"installing the markdownlint action dependencies"* ]]
  [ ! -s "$NPM_CALLS" ]
}

@test "no markdownlint action in the root -> installs nothing" {
  run_script
  [ "$status" -eq 0 ]
  [ ! -s "$NPM_CALLS" ]
}
