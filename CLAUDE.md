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
</project-context>
