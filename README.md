# couimet/github-actions

Shared composite GitHub Actions to keep CI bootstrap consistent across projects rather than copy-pasted into each one.

## Available actions

Listed alphabetically.

### `bats-test`

Runs [BATS](https://github.com/bats-core/bats-core) shell tests against a directory of `.bats` files. The step fails when any test fails.

| Input             | Required | Default  | Description                                                                          |
| ----------------- | -------- | -------- | ------------------------------------------------------------------------------------ |
| `assert-install`  | no       | `true`   | Install the `bats-assert` helper library.                                            |
| `bats-version`    | no       | `1.13.0` | BATS version installed; pinned so CI matches the local brew stable.                  |
| `detik-install`   | no       | `false`  | Install the `detik` helper library.                                                  |
| `file-install`    | no       | `false`  | Install the `bats-file` helper library.                                              |
| `formatter`       | no       | (empty)  | Passed as `--formatter` (e.g. `tap`, `junit`); empty uses the default pretty output. |
| `recursive`       | no       | `true`   | Recurse into subdirectories of `test-directory`.                                     |
| `support-install` | no       | `true`   | Install the `bats-support` helper library.                                           |
| `test-directory`  | no       | `tests/` | Directory containing `.bats` test files.                                             |

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

### `build`

Runs a build command. Defaults to `pnpm build`; override `command` for non-pnpm projects (e.g., `command: make build`). The step fails if the build fails.

| Input               | Required | Default      | Description                      |
| ------------------- | -------- | ------------ | -------------------------------- |
| `command`           | no       | `pnpm build` | Command to run for building.     |
| `working-directory` | no       | `.`          | Directory to run the command in. |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
  - uses: couimet/github-actions/build@main
```

### `check-no-prerelease-deps`

Scans all `package.json` files under the working directory for prerelease dependency patterns (`-alpha`, `-beta`, `-rc`, `-pre`) in `dependencies`, `devDependencies`, `peerDependencies`, and `optionalDependencies`. The step fails if any prerelease dependency is found. Used in CI to prevent accidentally depending on prerelease packages in main-branch PRs.

| Input               | Required | Default | Description                           |
| ------------------- | -------- | ------- | ------------------------------------- |
| `working-directory` | no       | `.`     | Directory to scan for `package.json`. |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/check-no-prerelease-deps@main
```

### `check-todos`

Counts `TODO` and `FIXME` comments across a configurable set of file extensions. On PRs, fetches the base ref and computes the delta to surface whether technical debt is being addressed or accumulated. The step never fails; it reports the count and delta as outputs and writes a markdown summary.

| Input             | Required | Default                                                                                                      | Description                                                                   |
| ----------------- | -------- | ------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `base-ref`        | no       | (empty)                                                                                                      | Base ref for PR delta comparison. When empty, reports the current count only. |
| `file-extensions` | no       | `ts,tsx,js,jsx,mjs,cjs,py,rb,go,rs,java,cs,sh,bash,yaml,yml,toml,md,html,css,scss,sql,tf,graphql,vue,svelte` | Comma-separated file extensions to scan (without leading dot).                |
| `path`            | no       | `.`                                                                                                          | Directory to scan for TODOs and FIXMEs.                                       |

| Output       | Description                                                      |
| ------------ | ---------------------------------------------------------------- |
| `todo-count` | Current `TODO`/`FIXME` count.                                    |
| `todo-delta` | Change vs base ref (PRs only, empty when `base-ref` is not set). |

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
      fetch-depth: 0
  - uses: couimet/github-actions/check-todos@main
```

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
      fetch-depth: 0
  - uses: couimet/github-actions/check-todos@main
    with:
      base-ref: ${{ github.event.pull_request.base.sha }}
```

### `coverage-comment`

Posts a PR comment with Jest coverage summaries and optional JUnit test stats. Wraps [MishaKav/jest-coverage-comment](https://github.com/MishaKav/jest-coverage-comment) with monorepo auto-discovery: when `coverage-summary-path` is not set, the action discovers all `coverage-summary.json` files under `working-directory` (excluding `node_modules`) and maps each to a per-package section in the comment. On subsequent pushes, the same comment is updated rather than creating duplicates.

The consuming workflow's job needs `pull-requests: write` in its `permissions:` block.

| Input                   | Required | Default           | Description                                                                                                           |
| ----------------------- | -------- | ----------------- | --------------------------------------------------------------------------------------------------------------------- |
| `coverage-summary-path` | no       | (empty)           | Path to a single `coverage-summary.json` file. When set, skips auto-discovery and uses this file directly.            |
| `create-new-comment`    | no       | `false`           | When `true`, creates a new comment on every push. When `false`, updates the existing comment.                         |
| `github-token`          | yes      | (none)            | GitHub token for posting PR comments. Pass `secrets.GITHUB_TOKEN` from the consuming workflow.                        |
| `junitxml-path`         | no       | (empty)           | Path to a JUnit XML file for test stats in the comment. Requires `jest-junit` in the consuming project's Jest config. |
| `title`                 | no       | `Coverage Report` | Title for the PR comment. In monorepos, per-package section titles are auto-derived from file paths.                  |
| `working-directory`     | no       | `.`               | Directory to search for `coverage-summary.json` files.                                                                |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
  - uses: couimet/github-actions/test@main
  - uses: couimet/github-actions/coverage-comment@main
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

### `format`

Runs a format command. Defaults to `pnpm format`; override `command` for non-pnpm projects (e.g., `command: make fmt`). The step fails if any file needs formatting.

| Input               | Required | Default       | Description                      |
| ------------------- | -------- | ------------- | -------------------------------- |
| `command`           | no       | `pnpm format` | Command to run for formatting.   |
| `working-directory` | no       | `.`           | Directory to run the command in. |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
  - uses: couimet/github-actions/format@main
```

### `guard-versions`

Blocks PRs from merging pre-release versions to `main`. Compares base and head SHAs for pre-release semver patterns (e.g., `0.1.0-alpha.1`) in changed `package.json` files. The step fails if any pre-release version is found.

| Input               | Required | Default                              | Description                   |
| ------------------- | -------- | ------------------------------------ | ----------------------------- |
| `base-ref`          | no       | `github.event.pull_request.base.sha` | Base ref for diff comparison. |
| `head-ref`          | no       | `github.event.pull_request.head.sha` | Head ref for diff comparison. |
| `working-directory` | no       | `.`                                  | Directory to run in.          |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
      fetch-depth: 0
  - uses: couimet/github-actions/guard-versions@main
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

### `lint`

Runs a lint command. Defaults to `pnpm lint`; override `command` for non-pnpm projects (e.g., `command: eslint . --max-warnings 0`). The step fails on any lint error.

| Input               | Required | Default     | Description                      |
| ------------------- | -------- | ----------- | -------------------------------- |
| `command`           | no       | `pnpm lint` | Command to run for linting.      |
| `working-directory` | no       | `.`         | Directory to run the command in. |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
  - uses: couimet/github-actions/lint@main
```

### `markdownlint`

Lints Markdown files with [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) at a pinned npm version. The step fails on any lint error.

| Input                  | Required | Default   | Description                                                                                                                        |
| ---------------------- | -------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `config`               | no       | (empty)   | Path to a config file passed as `--config`. When empty, auto-discovers all config files at the repo root (supports split configs). |
| `markdownlint-version` | no       | `0.22.1`  | Version of the `markdownlint-cli2` npm package; pinned for local/CI parity.                                                        |
| `paths`                | no       | `**/*.md` | Space-separated glob(s) of Markdown files to lint.                                                                                 |
| `working-directory`    | no       | `.`       | Directory to run markdownlint in. Set when the target lives in a subdirectory.                                                     |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: couimet/github-actions/markdownlint@main
```

### `prettier`

Checks formatting with [Prettier](https://prettier.io/) at a pinned npm version. The action honors the consuming repo's `.prettierrc*` and `.prettierignore` — defaulting to `.` paths lets the ignore file scope the check. The step fails when any file needs formatting.

| Input               | Required | Default | Description                                                                                                      |
| ------------------- | -------- | ------- | ---------------------------------------------------------------------------------------------------------------- |
| `config`            | no       | (empty) | Path passed as `--config`. When empty, Prettier auto-discovers `.prettierrc*` in the consuming repo.             |
| `paths`             | no       | `.`     | Space-separated path(s) passed to `prettier --check`; the consuming repo's `.prettierignore` governs exclusions. |
| `prettier-version`  | no       | `3.8.4` | Version of the `prettier` npm package installed globally; pinned for local/CI parity, overridable.               |
| `working-directory` | no       | `.`     | Directory to run Prettier in. Set when the target lives in a subdirectory.                                       |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/prettier@main
```

### `publish-pr-comment`

Posts a sticky PR comment. Thin wrapper around [marocchino/sticky-pull-request-comment](https://github.com/marocchino/sticky-pull-request-comment) so repos avoid duplicating the version pin and wiring across CI pipelines. The PR number defaults to the current pull request event; override `pr-number` for non-PR workflows or manual discovery.

The consuming workflow's job needs `pull-requests: write` in its `permissions:` block.

| Input          | Required | Default | Description                                                                                    |
| -------------- | -------- | ------- | ---------------------------------------------------------------------------------------------- |
| `comment-file` | yes      | (none)  | Path to a markdown file containing the comment body.                                           |
| `github-token` | yes      | (none)  | GitHub token for posting the comment. Pass `secrets.GITHUB_TOKEN` from the consuming workflow. |
| `header`       | yes      | (none)  | Unique header that identifies the comment across re-runs (enables sticky update behavior).     |
| `pr-number`    | no       | (empty) | PR number. When empty, defaults to `github.event.pull_request.number`.                         |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - name: Build comment body
    run: scripts/build-comment.sh > /tmp/comment-body.md
  - uses: couimet/github-actions/publish-pr-comment@main
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
      header: my-comment
      comment-file: /tmp/comment-body.md
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

### `shellcheck`

Lints shell scripts with [shellcheck](https://www.shellcheck.net/) (preinstalled on GitHub-hosted Ubuntu runners). Scripts are discovered via `find` with configurable extensions and exclusions. The step fails on any lint error.

| Input        | Required | Default                                   | Description                                                |
| ------------ | -------- | ----------------------------------------- | ---------------------------------------------------------- |
| `exclude`    | no       | `.claude-work .history node_modules .git` | Space-separated path fragments excluded from the `find`.   |
| `extensions` | no       | `sh bash`                                 | Space-separated file extensions to lint.                   |
| `paths`      | no       | `.`                                       | Root to search for shell scripts.                          |
| `severity`   | no       | (empty)                                   | Passed as `--severity` when set (e.g. `warning`, `error`). |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/shellcheck@main
```

### `test`

Runs a test command. Defaults to `pnpm test`; override `command` for non-pnpm projects. The step fails if any test fails.

| Input               | Required | Default     | Description                      |
| ------------------- | -------- | ----------- | -------------------------------- |
| `command`           | no       | `pnpm test` | Command to run for testing.      |
| `working-directory` | no       | `.`         | Directory to run the command in. |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
  - uses: couimet/github-actions/test@main
```

### `typescript-ci`

One-step CI for TypeScript projects. Bundles frequently-used CI steps into a single composite action. The input table below lists every bundled step and its toggle input. Use `typescript-ci` for the common case; use the individual actions when you need fine-grained control over step ordering, caching, or per-step timing.

The `coverage-comment` step posts a PR comment with Jest coverage summaries and optional test stats. It only runs on `pull_request` events. The consuming workflow's job needs `pull-requests: write` in its `permissions:` block.

| Input                      | Required | Default          | Description                                                                                                |
| -------------------------- | -------- | ---------------- | ---------------------------------------------------------------------------------------------------------- |
| `build-command`            | no       | `pnpm build`     | Command to run for building.                                                                               |
| `check-no-prerelease-deps` | no       | `true`           | Whether to check for prerelease dependency patterns in `package.json`.                                     |
| `check-todos`              | no       | `true`           | Whether to count TODOs and FIXMEs. On PRs, reports the delta vs the base branch.                           |
| `coverage-comment`         | no       | `true`           | Whether to post a coverage report as a PR comment after tests. Requires `pull-requests: write` on the job. |
| `format-command`           | no       | `pnpm format`    | Command to run for formatting.                                                                             |
| `guard-versions`           | no       | `true`           | Whether to run `guard-versions` (block pre-release versions on main).                                      |
| `lint-command`             | no       | `pnpm lint`      | Command to run for linting.                                                                                |
| `node-version`             | no       | (reads `.nvmrc`) | Node.js version override. When empty, reads `.nvmrc` from the consuming repo.                              |
| `test-command`             | no       | `pnpm test`      | Command to run for testing.                                                                                |
| `working-directory`        | no       | `.`              | Directory containing `package.json`.                                                                       |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/typescript-ci@main
```

For Turborepo monorepos, define root-level pnpm scripts that match the defaults so no overrides are needed (as done in `ts-npm-packages`):

```jsonc
"scripts": {
  "build": "turbo run build",
  "test": "turbo run test",
  "lint": "eslint . --max-warnings 0",
  "format": "prettier --check ."
}
```

When a command doesn't match the `pnpm <name>` convention, use the override inputs:

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/typescript-ci@main
    with:
      build-command: pnpm compile
```

## Available workflows

Listed alphabetically.

### `typescript-ci-checks`

Reusable workflow alternative to `typescript-ci`. Runs the same sub-actions as separate jobs so each produces its own PR status check. Use this when you want per-step visibility in the PR status section; use the composite `typescript-ci` action when you prefer fewer runner minutes and a single check entry.

| Input                      | Required | Default          | Description                                                                      |
| -------------------------- | -------- | ---------------- | -------------------------------------------------------------------------------- |
| `build-command`            | no       | `pnpm build`     | Command to run for building.                                                     |
| `check-no-prerelease-deps` | no       | `true`           | Whether to check for prerelease dependency patterns in `package.json`.           |
| `check-todos`              | no       | `true`           | Whether to count TODOs and FIXMEs. On PRs, reports the delta vs the base branch. |
| `coverage-comment`         | no       | `true`           | Whether to post a coverage report as a PR comment after tests.                   |
| `format-command`           | no       | `pnpm format`    | Command to run for formatting.                                                   |
| `guard-versions`           | no       | `true`           | Whether to run `guard-versions` (block pre-release versions on main).            |
| `lint-command`             | no       | `pnpm lint`      | Command to run for linting.                                                      |
| `node-version`             | no       | (reads `.nvmrc`) | Node.js version override. When empty, reads `.nvmrc` from the consuming repo.    |
| `test-command`             | no       | `pnpm test`      | Command to run for testing.                                                      |
| `working-directory`        | no       | `.`              | Directory containing `package.json`.                                             |

```yaml
jobs:
  ci:
    uses: couimet/github-actions/.github/workflows/typescript-ci-checks.yml@main
    with:
      working-directory: .
```

Each job runs in parallel and appears as a separate check:

```text
CI / format
CI / lint
CI / build
CI / test
CI / guard-versions
CI / check-no-prerelease-deps
CI / check-todos
```

Toggle off individual jobs with their boolean inputs (e.g., `guard-versions: false`). The `coverage-comment` step inside the test job only runs on `pull_request` events.

## Development

| Target                 | What                                                                                                |
| ---------------------- | --------------------------------------------------------------------------------------------------- |
| `make check`           | Run `lint`, `test`, and `check-actions` — the same gate CI runs on push.                            |
| `make fmt-check`       | Check formatting with Prettier; exits non-zero if any file needs formatting.                        |
| `make format`          | Apply Prettier formatting to all supported files.                                                   |
| `make install-prereqs` | Check that required system tools are installed and print install instructions for any missing tool. |
| `make lint`            | Run `lint-md`, `fmt-check`, and `lint-sh`.                                                          |
| `make lint-fix`        | Run `lint-md-fix` and `format`.                                                                     |
| `make test`            | Run BATS shell tests.                                                                               |

Fine-grained targets (`check-actions`, `lint-md`, `lint-md-fix`, `lint-sh`) are available for individual tool runs. Run `make install-prereqs` to verify your dev environment before `make check`.

## Versioning

Consumers reference actions with `@main` for now, which keeps friction low while the action set is small and every consumer is under the same maintainer. No version tags exist yet. When the first stable release cycle warrants it, this repository will adopt per-action compound tags (`setup-node-pnpm/v1.2.3`, `install-deps/v1.0.0`, and so on). See [`docs/ADR/`](./docs/ADR/) for the rationale and the migration plan.

## Documentation

- [`docs/ADR/`](./docs/ADR/) — architectural decision records (versioning policy, scope decisions, design choices).
