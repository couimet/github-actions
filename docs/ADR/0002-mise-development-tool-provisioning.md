# ADR-0002: mise for Development Tool Provisioning

- **Status:** Accepted
- **Date:** 2026-09-09
- **Deciders:** @couimet

## Context

Contributors provisioned this repository's development tools by hand. The Makefile `install-prereqs` target probed for `node`, `bats`, `shellcheck`, `uv`, and `jq` with `command -v` and printed Homebrew install lines for whatever was missing. Nothing declared the tested versions of those tools for local use: `node` came from whichever nvm version was active, and `shellcheck`, `uv`, and `jq` came from whatever the machine happened to have.

`versions.mk` pinned versions, but only the versions the shared actions bake as defaults for consumers. `scripts/verify-version-pins.sh` enforces those against each action's `action.yml` default or `package.json` devDependencies. The file was never a registry for this repository's own toolchain.

The consequence was that a contributor and CI could run different tool versions while both claimed to run the same gate, and a new contributor had to read the Makefile to learn which tools to install.

## Decision

Add a committed `mise.toml` at the repository root as the single declared toolchain for local development and CI, declaring `node`, `bats`, `shellcheck`, `uv`, and `jq`.

`mise.toml` is generated, not hand-edited. `scripts/generate-mise-toml.sh` reads `node` from `.nvmrc` and `bats` from `versions.mk` (`BATS_VERSION`), and declares the dev-only tools that no shared action pins — `shellcheck`, `uv`, and `jq` — as constants in the script. It supports a `--check` mode that fails when the committed file has drifted from those sources.

Enforcement has two layers. `make check-actions` runs `generate-mise-toml.sh --check`, so local runs and push builds fail on drift. On pull requests, `.github/workflows/ci.yml` runs the `check-generated-drift` action with the generator, which posts a sticky comment listing the drifted files.

The Makefile stays the task interface. `install-prereqs` becomes a mise delegation: it fails with an install pointer when mise is absent, runs `mise install` when present, and then verifies the five tools resolve on `PATH`, failing with an activation pointer when they do not.

CI provisions the toolchain through a new first-party composite action, `setup-mise`, which wraps `jdx/mise-action` pinned to a commit SHA, following the `publish-pr-comment` pattern so consumers do not duplicate the pin and wiring.

`versions.mk` keeps its role unchanged. It remains the contract for versions the shared actions bake for consumers; the generator reads `BATS_VERSION` from it, and a comment in the file records the boundary so the three dev-only tools are not added there.

## Consequences

### Positive

- One declared toolchain: a contributor and CI resolve the same five tool versions from one file.
- Drift is caught automatically. Editing `.nvmrc` or `BATS_VERSION` without regenerating `mise.toml` fails `make check-actions` and posts a pull request comment.
- A new contributor gets one instruction instead of a per-tool install list.
- The boundary between consumer-facing pins and this repository's dev-only tools is written down in `versions.mk`.

### Negative

- `make lint` and `make test` can trigger a network install on a fresh checkout, because `install-prereqs` runs `mise install`. The install is a no-op once the tools are present.
- The `node`, `bats`, and `uv` pins are not exercised by the CI self-test job, whose steps self-provision those tools. Only the pinned `shellcheck` and `jq` are exercised there; the rest are validated by local contributors.
- Bumping a dev-only tool version means editing `scripts/generate-mise-toml.sh`, not `mise.toml`.

## Follow-up

Honouring a consumer's `mise.toml` in the shared actions and reusable workflows is out of scope for this decision and is tracked separately: <https://github.com/couimet/github-actions/issues/133>.
