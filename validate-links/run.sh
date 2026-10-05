#!/usr/bin/env bash
set -euo pipefail

# Run lychee on the given paths.
#
# Inputs (env):
#   PATHS              space-separated paths or globs to check (default: **/*.md)
#   WORKING_DIRECTORY  directory to run in (default: .)

cd "${WORKING_DIRECTORY:-.}"

# Keep globs unexpanded: quoted array expansion prevents shell globbing, and
# lychee resolves ** globs itself.
IFS=' ' read -r -a PATH_ARGS <<< "${PATHS:-**/*.md}"

# --hidden: lychee skips hidden directories by default; include them so
# markdown under .github/ and .claude/ is covered by ** globs.
# --exclude-all-private: block private, link-local, and loopback targets; the
# workflow runs on pull_request events over contributor-controlled markdown.
# --exclude-path: skip vendored dependencies, because markdownlint and prettier
# exclude node_modules through their own ignore files and no equivalent ignore
# file covers a ** glob. An exclusion a repository wants for its own links belongs
# in its lychee.toml, which lychee reads from the working directory.
lychee --hidden --exclude-all-private --exclude-path 'node_modules' --no-progress "${PATH_ARGS[@]}"
