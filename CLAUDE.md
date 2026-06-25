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
  <do>Pin every third-party action (e.g. `actions/checkout`) to a full commit SHA with a `# vX.Y.Z` version comment</do>
  <never>Use floating version refs like `@v4` or `@main` for third-party actions</never>
  <good-example>
    ```yaml
    uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
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

<rule id="Q001" priority="critical">
  <title>Questions go to file via /question when there is ambiguity</title>
  <do>Use the `/question` skill as soon as there is ambiguity that needs clearing — choices between approaches, unclear requirements, design decisions that could go multiple ways</do>
  <never>Print questions directly in terminal output; never guess when a clarification would change the implementation</never>
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
