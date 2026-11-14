#!/usr/bin/env bash
set -euo pipefail

# Build kcov from source at a pinned commit and put it on PATH.
#
# kcov is not packaged for Ubuntu 24.04, so `apt-get install kcov` fails there
# and the action compiles it instead. The archive is checksum-verified before
# extraction. validate-links/install.sh established the sha256sum/shasum
# fallback used below; the comparison differs only because a GitHub archive has
# no published .sha256 asset to hand to `sha256sum -c`.
#
# Interface (all via environment):
#   KCOV_COMMIT       required. The kcov commit to build.
#   KCOV_SHA256       required. sha256 of that commit's GitHub archive tarball.
#   KCOV_INSTALL_DIR  optional. Install prefix, and the directory the caller
#                     caches. Default: ${RUNNER_TOOL_CACHE:-/tmp}/kcov/<commit>
#   GITHUB_PATH       optional. Appended to when set, so later steps see kcov.
#
# The caller restores KCOV_INSTALL_DIR from cache before this runs, so a
# previously built kcov means the compile is already paid for. The package
# install below still runs in that case: kcov is dynamically linked against
# libcurl, libssl, libelf, libdw, and zlib, so a restored binary on a runner
# without them exists and cannot start. The cache saves the compile, not the
# runtime.

KCOV_COMMIT="${KCOV_COMMIT:-}"
KCOV_SHA256="${KCOV_SHA256:-}"

if [[ -z "$KCOV_COMMIT" ]]; then
  echo "ERROR: KCOV_COMMIT is required" >&2
  exit 1
fi
if [[ -z "$KCOV_SHA256" ]]; then
  echo "ERROR: KCOV_SHA256 is required" >&2
  exit 1
fi

KCOV_INSTALL_DIR="${KCOV_INSTALL_DIR:-${RUNNER_TOOL_CACHE:-/tmp}/kcov/${KCOV_COMMIT}}"
KCOV_BIN_DIR="${KCOV_INSTALL_DIR}/bin"

# A runner image that already ships kcov needs nothing from us, and neither does
# a consumer that installed it in an earlier step. This branch returns before
# the package install because a pre-existing kcov already has its libraries.
if command -v kcov >/dev/null 2>&1; then
  echo "kcov already on PATH; nothing to install."
  exit 0
fi

echo "Installing kcov build and runtime dependencies..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  binutils-dev \
  build-essential \
  cmake \
  libcurl4-openssl-dev \
  libdw-dev \
  libelf-dev \
  libiberty-dev \
  libssl-dev \
  pkg-config \
  python3 \
  zlib1g-dev

# A cache hit skips the compile, but it must still write GITHUB_PATH: the cache
# restores files and not the job's PATH, so a freshly restored kcov is not on
# PATH in this job. Without this branch the first cache hit would fail the
# coverage step's own prerequisite check with "kcov: command not found", which
# reads as a coverage bug rather than as a cache bug.
if [[ -x "${KCOV_BIN_DIR}/kcov" ]]; then
  echo "Reusing cached kcov at ${KCOV_BIN_DIR}/kcov."
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${KCOV_BIN_DIR}" >> "${GITHUB_PATH}"
  fi
  exit 0
fi

ARCHIVE_URL="https://github.com/SimonKagstrom/kcov/archive/${KCOV_COMMIT}.tar.gz"
TARBALL="kcov-${KCOV_COMMIT}.tar.gz"

# Download into a unique temp dir so a pre-created path cannot be substituted,
# and remove it on every exit.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# macOS lacks sha256sum; shasum -a 256 is its portable equivalent.
verify_checksum() {
  local expected="$1" file="$2" actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "ERROR: no sha256 checksum tool found (need sha256sum or shasum)" >&2
    return 1
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: checksum mismatch for ${file}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    echo "  Refusing to build from an unverified archive." >&2
    return 1
  fi
}

echo "Downloading kcov ${KCOV_COMMIT}..."
curl -fsSL --connect-timeout 10 --max-time 300 "${ARCHIVE_URL}" -o "${TMP_DIR}/${TARBALL}"
verify_checksum "${KCOV_SHA256}" "${TMP_DIR}/${TARBALL}"

tar -xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"
SRC_DIR="${TMP_DIR}/kcov-${KCOV_COMMIT}"
if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: expected the source tree at ${SRC_DIR} after extraction" >&2
  exit 1
fi

# python3 is required, not decorative: the build fails while generating
# src/bash-cloexec-library.cc without it. GitHub runners carry python3 in the
# image, so the omission is invisible in CI and fatal on a minimal container.
BUILD_DIR="${TMP_DIR}/build"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$KCOV_INSTALL_DIR"
cmake --build "$BUILD_DIR" --parallel "$(nproc 2>/dev/null || echo 2)"
cmake --install "$BUILD_DIR"

if [[ ! -x "${KCOV_BIN_DIR}/kcov" ]]; then
  echo "ERROR: kcov binary not found at ${KCOV_BIN_DIR}/kcov after install" >&2
  exit 1
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${KCOV_BIN_DIR}" >> "${GITHUB_PATH}"
fi

echo "Installed kcov to ${KCOV_BIN_DIR}/kcov."
