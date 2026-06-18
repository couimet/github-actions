# couimet/github-actions

Shared composite GitHub Actions to keep CI bootstrap consistent across projects rather than copy-pasted into each one.

## Available actions

Listed alphabetically.

### `bats-test`

Runs [BATS](https://github.com/bats-core/bats-core) shell tests against a directory of `.bats` files. The step fails when any test fails.

| Input             | Required | Default  | Description                                                                          |
| ----------------- | -------- | -------- | ------------------------------------------------------------------------------------ |
| `test-directory`  | no       | `tests/` | Directory containing `.bats` test files.                                             |
| `bats-version`    | no       | `1.13.0` | BATS version installed; pinned so CI matches the local brew stable.                  |
| `support-install` | no       | `false`  | Install the `bats-support` helper library.                                           |
| `assert-install`  | no       | `false`  | Install the `bats-assert` helper library.                                            |
| `file-install`    | no       | `false`  | Install the `bats-file` helper library.                                              |
| `detik-install`   | no       | `false`  | Install the `detik` helper library.                                                  |
| `formatter`       | no       | (empty)  | Passed as `--formatter` (e.g. `tap`, `junit`); empty uses the default pretty output. |
| `recursive`       | no       | `false`  | Recurse into subdirectories of `test-directory`.                                     |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/bats-test@main
    with:
      test-directory: tests/shell
```

### `install-deps`

Restores the pnpm store from cache and runs `pnpm install --frozen-lockfile`.

| Input               | Required | Default | Description                                               |
| ------------------- | -------- | ------- | --------------------------------------------------------- |
| `working-directory` | no       | `.`     | Directory containing `package.json` and `pnpm-lock.yaml`. |

| Output      | Description                                                            |
| ----------- | ---------------------------------------------------------------------- |
| `cache-hit` | `true` when the pnpm store cache was restored from an exact key match. |

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
```

### `markdownlint`

Lints Markdown files with [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) at a pinned npm version. The step fails on any lint error.

| Input                  | Required | Default   | Description                                                                                                                        |
| ---------------------- | -------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `markdownlint-version` | no       | `0.22.1`  | Version of the `markdownlint-cli2` npm package; pinned for local/CI parity.                                                        |
| `config`               | no       | (empty)   | Path to a config file passed as `--config`. When empty, auto-discovers all config files at the repo root (supports split configs). |
| `globs`                | no       | `**/*.md` | Glob(s) of Markdown files to lint.                                                                                                 |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: couimet/github-actions/markdownlint@main
```

### `setup-node-pnpm`

Installs Node.js (reading the version from the consuming repo's `.nvmrc` unless overridden) and activates pnpm via Corepack from the consuming repo's `package.json` `packageManager` field.

| Input               | Required | Default          | Description                                                                                                                                                               |
| ------------------- | -------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `node-version`      | no       | (reads `.nvmrc`) | Overrides `.nvmrc` when set.                                                                                                                                              |
| `working-directory` | no       | `.`              | Directory containing the `package.json` whose `packageManager` field Corepack should resolve. Set this when `package.json` lives in a subdirectory (e.g. a test fixture). |

| Output         | Description                            |
| -------------- | -------------------------------------- |
| `node-version` | Resolved Node.js version.              |
| `pnpm-version` | Resolved pnpm version (from Corepack). |

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
```

## Development

| Target                 | What                                                                                                |
| ---------------------- | --------------------------------------------------------------------------------------------------- |
| `make check`           | Run `lint` and `test` — the same gate CI runs on push.                                              |
| `make fmt-check`       | Check formatting with Prettier; exits non-zero if any file needs formatting.                        |
| `make format`          | Apply Prettier formatting to all supported files.                                                   |
| `make install-prereqs` | Check that required system tools are installed and print install instructions for any missing tool. |
| `make lint`            | Run `lint-md`, `fmt-check`, and `lint-sh`.                                                          |
| `make lint-fix`        | Run `lint-md-fix` and `format`.                                                                     |
| `make test`            | Run BATS shell tests.                                                                               |

Fine-grained targets (`lint-md`, `lint-md-fix`, `lint-sh`) are available for individual tool runs. Run `make install-prereqs` to verify your dev environment before `make check`.

## Versioning

Consumers reference actions with `@main` for now, which keeps friction low while the action set is small and every consumer is under the same maintainer. No version tags exist yet. When the first stable release cycle warrants it, this repository will adopt per-action compound tags (`setup-node-pnpm/v1.2.3`, `install-deps/v1.0.0`, and so on). See [`docs/ADR/`](./docs/ADR/) for the rationale and the migration plan.

## Documentation

- [`docs/ADR/`](./docs/ADR/) — architectural decision records (versioning policy, scope decisions, design choices).
