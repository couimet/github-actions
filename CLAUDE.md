# Claude Code Instructions

<meta>
  <purpose>Project-specific instructions for Claude Code</purpose>
  <project>github-actions — Reusable GitHub Actions (composite + workflows)</project>
  <version>2.0 - XML-structured format</version>
</meta>

---

<critical-rules>
<!-- These rules are checked on EVERY response. Violations are unacceptable. -->

<rule id="CI001" priority="critical">
  <title>Third-party actions pinned to commit SHA</title>
  <do>Pin every third-party action (e.g. `actions/checkout`) to a full commit SHA WITHOUT a `# vX.Y.Z` version comment to prevent drift</do>
  <never>Use floating version refs like `@v4` or `@main` for third-party actions</never>
  <good-example>
    ```yaml
    uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10
    ```
  </good-example>
  <bad-example>
    ```yaml
    uses: actions/checkout@v4
    ```
  </bad-example>
</rule>

<rule id="CI002" priority="critical">
  <title>Internal actions always use @main, never a commit SHA</title>
  <do>Reference all `couimet/github-actions/*` actions with `@main`: `uses: couimet/github-actions/typescript-ci@main`</do>
  <never>Pin to a commit SHA or tag for `couimet/github-actions` actions</never>
  <rationale>`@main` is the intended rolling release channel for first-party actions. We control the repo, so breaking changes are intentional and versioned. SHAs add pin-update churn with no benefit for actions we own.</rationale>
</rule>

<rule id="CI003" priority="critical">
  <title>Composite actions reference internal actions by full path, not ./</title>
  <do>In composite action `action.yml` files, reference other `couimet/github-actions/*` actions with the full `couimet/github-actions/<name>@main` path</do>
  <never>Use `./` relative paths or `${{ github.action_path }}` expressions in `uses:` — `./` resolves to the consumer's workspace, and expressions are forbidden in `uses:` fields</never>
  <rationale>GitHub Actions resolves `./` paths in composite actions relative to the consuming repository's workspace. The `${{ github.action_path }}` expression would point to the action's own repo, but GitHub Actions forbids expressions in `uses:` fields entirely. The only portable option is the full `owner/repo/path@main` reference.</rationale>
  <good-example>
    ```yaml
    uses: couimet/github-actions/publish-pr-comment@main
    ```
  </good-example>
  <bad-example>
    ```yaml
    uses: ./publish-pr-comment
    ```
  </bad-example>
  <bad-example>
    ```yaml
    # Also invalid: expressions are forbidden in uses:
    uses: ${{ github.action_path }}/publish-pr-comment
    ```
  </bad-example>
</rule>

<rule id="Q001" priority="critical">
  <title>Questions go to file via /question when there is ambiguity</title>
  <do>Use the `/question` skill as soon as there is ambiguity that needs clearing — choices between approaches, unclear requirements, design decisions that could go multiple ways</do>
  <never>Print questions directly in terminal output; never guess when a clarification would change the implementation</never>
</rule>

<rule id="CI004" priority="critical">
  <title>Shell logic goes in .sh files, never inlined in run: blocks</title>
  <do>Extract non-trivial shell logic into a .sh file inside the action directory. Call it from action.yml via <code>bash &quot;$&#123;&#123; github.action_path }}&quot;/script.sh</code>. Receive inputs as environment variables (uppercase). Start every script with <code>#!/usr/bin/env bash</code> and <code>set -euo pipefail</code>.</do>
  <never>Inline shell scripts in workflow `run:` blocks or composite action `run:` fields when the logic spans more than one line</never>
  <rationale>.sh files are testable with BATS (full coverage). Inline `run:` blocks can only be exercised in live CI. Keeping scripts in files also makes the action directory self-contained: action.yml + script.sh + BATS test.</rationale>
  <good-example>
    ```yaml
    # action.yml — script called via github.action_path:
    - name: Discover coverage files
      shell: bash
      env:
        WORKING_DIRECTORY: ${{ inputs.working-directory }}
      run: bash "${{ github.action_path }}/discover.sh"
    ```
  </good-example>
  <bad-example>
    ```yaml
    # action.yml — inline shell in run: is not testable:
    - shell: bash
      run: |
        curl -Os https://uploader.codecov.io/latest/linux/codecov
        chmod +x codecov
        for f in ${{ inputs.files }}; do
          ./codecov -f "$f" -F "$pkg"
        done
    ```
  </bad-example>
</rule>

</critical-rules>

---

<autonomous-operations>

<allowed-actions>
<!-- Claude proceeds without asking permission for these -->
<action>Reading files — any project files for context</action>
<action>Running tests — `make test`, `bats tests/`</action>
<action>Git status — `git status`, `git log`, `git diff`</action>
<action>Searching code — grep, find, ripgrep</action>
<action>Editing files — bug fixes, features, refactoring</action>
<action>Writing new files — when required (prefer editing existing)</action>
</allowed-actions>

<default-behavior>
<behavior>Be proactive — if tests fail, investigate and fix without asking</behavior>
<behavior>Run verification — after changes, automatically run tests</behavior>
<behavior>Self-correct — if command fails, try alternatives</behavior>
<behavior>Provide context — explain actions but don't wait for routine approval</behavior>
<behavior>Use parallel operations — run independent commands concurrently</behavior>
</default-behavior>

</autonomous-operations>

---

<project-context>
  <name>github-actions</name>
  <description>
    Reusable GitHub Actions for various type of projects (although mainly developed around TypeScript/Node.js projects). Provides composite
    actions (format, lint, build, test, guard-versions, coverage-comment, etc.)
    and reusable workflows that runs each check as a
    separate job for per-step CI visibility.
  </description>
  <tech>
    - Composite actions in repo root (each has action.yml)
    - Reusable workflows in .github/workflows/
    - Shell tests use BATS (bats-core)
    - CI self-tests actions against tests/ fixture
    - Formatting enforced by Prettier
  </tech>
  <actions>
    <!-- Compact action index, alphabetical like README.md "Available actions". README is the single source of truth for each action's full contract (inputs, outputs, usage); the index rows carry only a one-line purpose. Before modifying an action, read its README section, its action.yml, and its BATS suite. -->
    <action name="auto-fix">Runs a fix command and auto-commits any resulting changes with a `[skip ci]` message</action>
    <action name="bats-test">Runs BATS tests via SHA-pinned bats-core/bats-action; optionally posts results as a sticky PR comment</action>
    <action name="build">Runs a build command (default `pnpm build`)</action>
    <action name="check-generated-drift">Regenerates files and fails if git detects drift; posts a comment listing out-of-sync files</action>
    <action name="check-no-prerelease-deps">Fails if any package.json declares a prerelease npm dependency</action>
    <action name="check-todos">Counts TODOs/FIXMEs; on PRs reports the delta vs the base branch</action>
    <action name="codecov-typescript-upload">Uploads Jest coverage to Codecov, with optional per-package flags</action>
    <action name="codecov-upload">Language-agnostic Codecov upload; prefer codecov-typescript-upload for Jest coverage</action>
    <action name="coverage-comment">Posts a PR comment with Jest coverage summaries and optional JUnit test stats</action>
    <action name="detect-auto-fix-commit">Outputs whether the head commit is an auto-fix commit</action>
    <action name="format">Runs a format command (default `pnpm format`)</action>
    <action name="guard-versions">Blocks PRs from merging pre-release versions to main</action>
    <action name="install-deps">Restores the pnpm store from cache and runs `pnpm install --frozen-lockfile`</action>
    <action name="lint">Runs a lint command (default `pnpm lint`)</action>
    <action name="markdownlint">Installs markdownlint-cli2 at a pinned version and lints or fixes Markdown files</action>
    <action name="prettier">Installs Prettier at a pinned version and checks or fixes formatting against the repo config</action>
    <action name="publish-pr-comment">Posts a sticky PR comment; thin wrapper around marocchino/sticky-pull-request-comment</action>
    <action name="request-coderabbit-full-review">Posts a @coderabbitai full review comment to trigger a fresh CodeRabbit review</action>
    <action name="setup-node-pnpm">Installs Node.js from .nvmrc (overridable) and activates pnpm via Corepack</action>
    <action name="shellcheck">Discovers shell scripts (including extensionless) and runs shellcheck</action>
    <action name="test">Runs a test command (default `pnpm test`)</action>
    <action name="typescript-ci">One-step CI orchestrator chaining 12 internal actions (setup, install, format, lint, build, test, coverage, codecov, guards, checks, auto-fix)</action>
    <action name="validate-yaml">Validates a YAML file against a JSON Schema; posts a comment on failure</action>
  </actions>
  <conventions>
    - Entrypoint, pinning, and reference rules: see CI001-CI004 in <critical-rules>
    - Each action with a script has a BATS suite at bats-tests/shell/<action>.bats; repo-integrity checks live in verify-*.bats
    - typescript-ci is the only orchestrator action; all other actions are leaf steps
    - Context dirs: bats-tests/ holds this repo's own suites (default test-directory for consuming repos), scripts/ has verify helpers run by make check-actions, tests/ is the Jest fixture used in CI; reusable workflows live in .github/workflows/
  </conventions>
</project-context>
