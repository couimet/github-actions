# couimet/github-actions

Shared composite GitHub Actions to keep CI bootstrap consistent across projects rather than copy-pasted into each one.

[![codecov](https://codecov.io/gh/couimet/github-actions/branch/main/graph/badge.svg)](https://codecov.io/gh/couimet/github-actions)

## Available actions

Listed alphabetically.

### `auto-fix`

Runs a fix command (e.g., `pnpm format:fix && pnpm lint:fix`) and auto-commits any resulting changes. Thin wrapper around [stefanzweifel/git-auto-commit-action](https://github.com/stefanzweifel/git-auto-commit-action) pinned to a commit SHA, so consuming repos avoid duplicating the pin. The default commit message (`chore: auto-fix [skip ci]`) includes the `[skip ci]` token, which prevents the auto-commit from triggering another CI run — without it, the fix commit would re-trigger the pipeline and risk an infinite CI loop. Keep the `[skip ci]` token in the message when overriding `commit-message`; dropping it only re-triggers CI when the workflow is called with the `auto-fix-token` secret. The workflow's recursion guard matches the head commit subject against the configured message, so keep the message a single line, and keep the fix command idempotent as a backstop.

The consuming workflow's job needs `contents: write` in its `permissions:` block. On `pull_request` events, the caller must check out the PR head ref with `persist-credentials: true` so the auto-fix commit can be pushed instead of failing on a detached HEAD.

| Input               | Required | Default                                        | Description                                                                                                                                                                                                                                                           |
| ------------------- | -------- | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `commit-message`    | no       | `chore: auto-fix [skip ci]`                    | Commit message for the auto-fix commit. Keep the `[skip ci]` token when overriding; dropping it only re-triggers CI when the workflow is called with the `auto-fix-token` secret, and the recursion guard matches the head commit subject against this exact message. |
| `commit-user-email` | no       | `github-actions[bot]@users.noreply.github.com` | Email for the auto-fix commit author.                                                                                                                                                                                                                                 |
| `commit-user-name`  | no       | `github-actions[bot]`                          | Name for the auto-fix commit author.                                                                                                                                                                                                                                  |
| `fix-command`       | yes      | (none)                                         | Shell command to run for auto-fixing (e.g., `pnpm format:fix && pnpm lint:fix`).                                                                                                                                                                                      |
| `working-directory` | no       | `.`                                            | Directory to run the fix command in.                                                                                                                                                                                                                                  |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: true
      ref: ${{ github.event.pull_request.head.ref }}
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
  - uses: couimet/github-actions/auto-fix@main
    with:
      fix-command: pnpm format:fix && pnpm lint:fix
```

Prefer pre-commit hooks (e.g., Husky + lint-staged) over CI auto-fix: hooks fix issues before they leave the developer's machine, with no CI permission elevation and no extra CI runs. Auto-fix is best used as a safety net for contributors who bypass hooks — keep the CI format/lint check as a read-only gate and let the auto-fix commit be the fix path. See the CodeRabbit analysis in [issue #28](https://github.com/couimet/github-actions/issues/28) for the full trade-offs.

### `bats-test`

Runs [BATS](https://github.com/bats-core/bats-core) shell tests against a directory of `.bats` files. The step fails when any test fails. By default, posts a sticky PR comment with test result counts via `publish-pr-comment` (set `publish-comment: 'false'` to opt out). The consuming workflow's job needs `pull-requests: write` in its `permissions:` block when comment publishing is active.

| Input             | Required | Default             | Description                                                                          |
| ----------------- | -------- | ------------------- | ------------------------------------------------------------------------------------ |
| `assert-install`  | no       | `true`              | Install the `bats-assert` helper library.                                            |
| `bats-version`    | no       | `1.13.0`            | BATS version installed; pinned so CI matches the local brew stable.                  |
| `comment-header`  | no       | `BATS Test Results` | Unique header that identifies the BATS comment across re-runs (sticky update).       |
| `detik-install`   | no       | `false`             | Install the `detik` helper library.                                                  |
| `file-install`    | no       | `false`             | Install the `bats-file` helper library.                                              |
| `formatter`       | no       | (empty)             | Passed as `--formatter` (e.g. `tap`, `junit`); empty uses the default pretty output. |
| `github-token`    | no       | (empty)             | GitHub token for posting the comment. Required only when `publish-comment` is true.  |
| `publish-comment` | no       | `true`              | Post a sticky PR comment with test result counts. Set to `false` to opt out.         |
| `recursive`       | no       | `true`              | Recurse into subdirectories of `test-directory`.                                     |
| `support-install` | no       | `true`              | Install the `bats-support` helper library.                                           |
| `test-directory`  | no       | `bats-tests/`       | Directory containing `.bats` test files.                                             |

When `publish-comment` is true (the default), the action exposes these outputs:

| Output      | Description                                                                |
| ----------- | -------------------------------------------------------------------------- |
| `total`     | Total test cases parsed from TAP output.                                   |
| `passed`    | Number of passing tests.                                                   |
| `failed`    | Number of failing tests (0 when all pass).                                 |
| `exit_code` | BATS exit code: 0 = all passed, 1 = one or more failures, >1 = BATS error. |

When `publish-comment` is false, no outputs are set; success or failure is reported through the step exit code alone.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/bats-test@main
    with:
      test-directory: bats-tests/shell
      github-token: ${{ secrets.GITHUB_TOKEN }}
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

### `check-generated-drift`

Runs a configurable command (e.g., `pnpm api:types`, `make generate`) and fails if `git diff` detects any uncommitted changes. On drift, posts a sticky PR comment listing the files that are out of sync. Use this to guard against PRs that edit a source spec without re-running codegen.

| Input               | Required | Default                 | Description                                                                  |
| ------------------- | -------- | ----------------------- | ---------------------------------------------------------------------------- |
| `command`           | yes      | (none)                  | Shell command that regenerates generated files.                              |
| `post-generate`     | no       | (empty)                 | Optional hook that runs after generation but before drift detection.         |
| `github-token`      | yes      | (none)                  | GitHub token for posting PR comments. Pass `secrets.GITHUB_TOKEN`.           |
| `header`            | no       | `Generated drift check` | Unique header that identifies the PR comment across re-runs (sticky update). |
| `working-directory` | no       | `.`                     | Directory to run the command in.                                             |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
  - uses: couimet/github-actions/check-generated-drift@main
    with:
      command: pnpm api:types
      github-token: ${{ secrets.GITHUB_TOKEN }}
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

### `codecov-typescript-upload`

Uploads a Jest coverage report to Codecov. Thin wrapper around [codecov/codecov-action](https://github.com/codecov/codecov-action) with TypeScript/Jest defaults. For non-JS projects, use the generic `codecov-upload` action instead.

| Input               | Required | Default              | Description                                                              |
| ------------------- | -------- | -------------------- | ------------------------------------------------------------------------ |
| `files`             | no       | `coverage/lcov.info` | Coverage report file(s) to upload (glob).                                |
| `working-directory` | no       | `.`                  | Directory to run in. Coverage file paths are relative to this directory. |
| `flags`             | no       | (empty)              | Codecov flags to apply to the upload (e.g. `unit`, `integration`).       |
| `token`             | no       | (empty)              | Codecov upload token. Not needed for public repos.                       |
| `fail-ci-if-error`  | no       | `false`              | When `true`, fails the CI step if the upload fails.                      |

This action has no outputs; success or failure is reported through the step exit code, although Codecov upload failures do not fail the step by default (set `fail-ci-if-error` to `true` to change that).

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/setup-node-pnpm@main
  - uses: couimet/github-actions/install-deps@main
  - uses: couimet/github-actions/test@main
  - uses: couimet/github-actions/codecov-typescript-upload@main
```

### `codecov-upload`

Uploads a coverage report to Codecov. Language-agnostic wrapper around [codecov/codecov-action](https://github.com/codecov/codecov-action). For TypeScript/Jest projects, use `codecov-typescript-upload` for sensible defaults.

| Input               | Required | Default | Description                                                              |
| ------------------- | -------- | ------- | ------------------------------------------------------------------------ |
| `files`             | yes      | (none)  | Coverage report file(s) to upload (glob).                                |
| `working-directory` | no       | `.`     | Directory to run in. Coverage file paths are relative to this directory. |
| `flags`             | no       | (empty) | Codecov flags to apply to the upload (e.g. `unit`, `integration`).       |
| `token`             | no       | (empty) | Codecov upload token. Not needed for public repos.                       |
| `fail-ci-if-error`  | no       | `false` | When `true`, fails the CI step if the upload fails.                      |

This action has no outputs; success or failure is reported through the step exit code, although Codecov upload failures do not fail the step by default (set `fail-ci-if-error` to `true` to change that).

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/test@main
    with:
      command: make test-coverage
  - uses: couimet/github-actions/codecov-upload@main
    with:
      files: build/coverage/lcov.info
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

### `detect-auto-fix-commit`

Outputs whether the head commit subject matches a configured auto-fix commit message. This is the recursion guard the `typescript-ci-checks` workflow uses to skip its own fix commits: read `outputs.is-auto-fix` and skip the auto-fix step when it is `'true'`.

| Input            | Required | Default | Description                                               |
| ---------------- | -------- | ------- | --------------------------------------------------------- |
| `commit-message` | yes      | (none)  | Commit subject that marks a commit as an auto-fix commit. |

`outputs.is-auto-fix` is `'true'` when the latest commit subject matches `commit-message`.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: couimet/github-actions/detect-auto-fix-commit@main
    id: guard
    with:
      commit-message: 'chore: auto-fix [skip ci]'
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

Lints Markdown files with [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) at a pinned npm version. In the default `check` mode the step fails on any lint error; set `mode: fix` to run `markdownlint-cli2 --fix` and fix issues in place instead.

| Input                  | Required | Default   | Description                                                                                                                        |
| ---------------------- | -------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `config`               | no       | (empty)   | Path to a config file passed as `--config`. When empty, auto-discovers all config files at the repo root (supports split configs). |
| `markdownlint-version` | no       | (empty)   | Version of `markdownlint-cli2`. When empty, uses the version from `package.json` (Dependabot-tracked). Set to override.            |
| `mode`                 | no       | `check`   | `check` performs a read-only lint (the default); `fix` runs `markdownlint-cli2 --fix` to fix issues in place.                      |
| `paths`                | no       | `**/*.md` | Space-separated glob(s) of Markdown files to lint.                                                                                 |
| `working-directory`    | no       | `.`       | Directory to run markdownlint in. Set when the target lives in a subdirectory.                                                     |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: couimet/github-actions/markdownlint@main
```

### `prettier`

Checks formatting with [Prettier](https://prettier.io/) at a pinned npm version. The action honors the consuming repo's `.prettierrc*` and `.prettierignore` — defaulting to `.` paths lets the ignore file scope the check. In the default `check` mode the step fails when any file needs formatting; set `mode: fix` to run `prettier --write` and fix files in place instead.

| Input               | Required | Default | Description                                                                                                    |
| ------------------- | -------- | ------- | -------------------------------------------------------------------------------------------------------------- |
| `config`            | no       | (empty) | Path passed as `--config`. When empty, Prettier auto-discovers `.prettierrc*` in the consuming repo.           |
| `mode`              | no       | `check` | `check` runs `prettier --check` (read-only, the default); `fix` runs `prettier --write` to fix files in place. |
| `paths`             | no       | `.`     | Space-separated path(s) passed to prettier; the consuming repo's `.prettierignore` governs exclusions.         |
| `prettier-version`  | no       | (empty) | Version of `prettier`. When empty, uses the version from `package.json` (Dependabot-tracked). Set to override. |
| `working-directory` | no       | `.`     | Directory to run Prettier in. Set when the target lives in a subdirectory.                                     |

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

| Input          | Required | Default   | Description                                                                                                           |
| -------------- | -------- | --------- | --------------------------------------------------------------------------------------------------------------------- |
| `comment-file` | yes      | (none)    | Path to a markdown file containing the comment body.                                                                  |
| `github-token` | yes      | (none)    | GitHub token for posting the comment. Pass `secrets.GITHUB_TOKEN` from the consuming workflow.                        |
| `header`       | yes      | (none)    | Unique header that identifies the comment across re-runs (enables sticky update behavior).                            |
| `pr-number`    | no       | (empty)   | PR number. When empty, defaults to `github.event.pull_request.number`.                                                |
| `create-new`   | no       | `'false'` | When true, append a unique suffix to the header so each run creates a new comment instead of updating a previous one. |

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

When `auto-fix-command` is set, an auto-fix step runs after format and lint and commits the fixes back to the branch. The consuming job must check out the PR head ref with `persist-credentials: true` and grant `contents: write` in its `permissions:` block. The step only runs on same-repository `pull_request` events, so fork PRs are skipped.

| Input                      | Required | Default          | Description                                                                                                                                                                                                                                                                                                                                   |
| -------------------------- | -------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `auto-fix-command`         | no       | (empty)          | Command to run for auto-fixing after format and lint (e.g., `pnpm format:fix && pnpm lint:fix`). When empty (the default), auto-fix is disabled; when set, runs an auto-fix step on same-repository `pull_request` events. Requires the PR head ref checked out with `persist-credentials: true` and `contents: write`; fork PRs are skipped. |
| `build-command`            | no       | `pnpm build`     | Command to run for building.                                                                                                                                                                                                                                                                                                                  |
| `check-no-prerelease-deps` | no       | `true`           | Whether to check for prerelease dependency patterns in `package.json`.                                                                                                                                                                                                                                                                        |
| `check-todos`              | no       | `true`           | Whether to count TODOs and FIXMEs. On PRs, reports the delta vs the base branch.                                                                                                                                                                                                                                                              |
| `coverage-comment`         | no       | `true`           | Whether to post a coverage report as a PR comment after tests. Requires `pull-requests: write` on the job.                                                                                                                                                                                                                                    |
| `format-command`           | no       | `pnpm format`    | Command to run for formatting.                                                                                                                                                                                                                                                                                                                |
| `guard-versions`           | no       | `true`           | Whether to run `guard-versions` (block pre-release versions on main).                                                                                                                                                                                                                                                                         |
| `lint-command`             | no       | `pnpm lint`      | Command to run for linting.                                                                                                                                                                                                                                                                                                                   |
| `node-version`             | no       | (reads `.nvmrc`) | Node.js version override. When empty, reads `.nvmrc` from the consuming repo.                                                                                                                                                                                                                                                                 |
| `test-command`             | no       | `pnpm test`      | Command to run for testing.                                                                                                                                                                                                                                                                                                                   |
| `working-directory`        | no       | `.`              | Directory containing `package.json`.                                                                                                                                                                                                                                                                                                          |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/typescript-ci@main
```

To enable auto-fix, check out the PR head ref with persisted credentials (the job needs `permissions: contents: write`):

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: true
      ref: ${{ github.event.pull_request.head.ref }}
  - uses: couimet/github-actions/typescript-ci@main
    with:
      auto-fix-command: pnpm format:fix && pnpm lint:fix
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

### `validate-yaml`

Validates a YAML file against a JSON Schema file. Uses Python (jsonschema + pyyaml) managed by uv for reproducible dependency resolution. The step fails if the YAML file does not conform to the schema.

| Input    | Required | Default | Description                        |
| -------- | -------- | ------- | ---------------------------------- |
| `schema` | yes      | (none)  | Path to the JSON Schema file.      |
| `file`   | yes      | (none)  | Path to the YAML file to validate. |

This action has no outputs; success or failure is reported through the step exit code.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false
  - uses: couimet/github-actions/validate-yaml@main
    with:
      schema: path/to/schema.json
      file: path/to/data.yml
```

## Available workflows

Listed alphabetically.

### `typescript-ci-checks`

Reusable workflow alternative to `typescript-ci`. Runs the same sub-actions as separate jobs so each produces its own PR status check. Use this when you want per-step visibility in the PR status section; use the composite `typescript-ci` action when you prefer fewer runner minutes and a single check entry.

The `test` job depends on `build` (`needs: [build]`). When the build fails, tests are skipped to surface the right failure fast. Pass compiled output (or any generated files) from build to test via `build-artifact-paths` to avoid recompiling in the test runner.

When `auto-fix-command` is set, an `auto-fix` job runs when format or lint fails, so it can fix the files that caused the failure, and commits the fixes back to the branch. By default the fix commit uses `chore: auto-fix [skip ci]` and is pushed with GITHUB_TOKEN, so no checks report on the fixed SHA and repos with required status checks stay merge-blocked until another commit lands. For the opt-in mode, pass the `auto-fix-token` secret (a PAT or GitHub App token) plus an `auto-fix-commit-message` without `[skip ci]`: the fix commit then re-triggers the pipeline so checks report green on the fixed SHA, while the auto-fix job skips its own commits by matching the head commit subject against the configured `auto-fix-commit-message`, and git-auto-commit-action no-ops when there is nothing to fix. The job runs with `contents: write` permission to push the fix commit.

| Input                      | Required | Default                     | Description                                                                                                                                                                                                      |
| -------------------------- | -------- | --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `auto-fix-command`         | no       | (empty)                     | Command to run for auto-fixing after format and lint (e.g., `pnpm format:fix && pnpm lint:fix`). When empty (the default), the auto-fix job is not added.                                                        |
| `auto-fix-commit-message`  | no       | `chore: auto-fix [skip ci]` | Commit message for the auto-fix commit. Keep the `[skip ci]` token unless paired with the `auto-fix-token` secret; the recursion guard matches the head commit subject against this exact message (single line). |
| `build-artifact-paths`     | no       | `packages/*/out/`           | Multi-line globs of build output to pass from the build job to the test job. Set to an empty string to disable the artifact upload/download.                                                                     |
| `build-command`            | no       | `pnpm build`                | Command to run for building.                                                                                                                                                                                     |
| `check-no-prerelease-deps` | no       | `true`                      | Whether to check for prerelease dependency patterns in `package.json`.                                                                                                                                           |
| `check-todos`              | no       | `true`                      | Whether to count TODOs and FIXMEs. On PRs, reports the delta vs the base branch.                                                                                                                                 |
| `codecov-files`            | no       | `coverage/lcov.info`        | Coverage report file(s) to upload (glob). Passed through to `codecov-typescript-upload`. Useful for monorepos (e.g., `packages/*/coverage/lcov.info`).                                                           |
| `codecov-token`            | no       | (empty)                     | Codecov upload token for private repos and fork PRs. Prefer the identically named `codecov-token` secret instead; this input is kept as a fallback.                                                              |
| `codecov-upload`           | no       | `true`                      | Whether to upload coverage to Codecov from the test job.                                                                                                                                                         |
| `coverage-comment`         | no       | `true`                      | Whether to post a coverage report as a PR comment after tests.                                                                                                                                                   |
| `format-command`           | no       | `pnpm format`               | Command to run for formatting.                                                                                                                                                                                   |
| `guard-versions`           | no       | `true`                      | Whether to run `guard-versions` (block pre-release versions on main).                                                                                                                                            |
| `lint-command`             | no       | `pnpm lint`                 | Command to run for linting.                                                                                                                                                                                      |
| `node-version`             | no       | (reads `.nvmrc`)            | Node.js version override. When empty, reads `.nvmrc` from the consuming repo.                                                                                                                                    |
| `test-command`             | no       | `pnpm test`                 | Command to run for testing.                                                                                                                                                                                      |
| `working-directory`        | no       | `.`                         | Directory containing `package.json`.                                                                                                                                                                             |

| Secret           | Required | Description                                                                                                                                                                                    |
| ---------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `auto-fix-token` | no       | Optional PAT or GitHub App token for the auto-fix push. When set, the fix commit can trigger a fresh CI run on the fixed SHA, paired with an `auto-fix-commit-message` that omits `[skip ci]`. |
| `codecov-token`  | no       | Codecov upload token. Use this instead of the input when passing `secrets.CODECOV_TOKEN` from the caller. Falls back to the input.                                                             |

```yaml
jobs:
  ci:
    uses: couimet/github-actions/.github/workflows/typescript-ci-checks.yml@main
    with:
      working-directory: .
    secrets:
      codecov-token: ${{ secrets.CODECOV_TOKEN }}
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

Toggle off individual jobs with their boolean inputs (e.g., `guard-versions: false`). The `coverage-comment` step inside the test job only runs on `pull_request` events. Coverage is uploaded to Codecov by default; set `codecov-upload: false` to disable.

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
