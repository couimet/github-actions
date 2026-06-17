# ADR-0001: Monorepo Tagging Strategy

- **Status:** Proposed
- **Date:** 2026-06-16
- **Deciders:** @couimet

## Context

This repository hosts several composite GitHub Actions in independent top-level directories (`setup-node-pnpm/`, `install-deps/`, and more to come). Consumers reference each action via `uses: couimet/github-actions/<action-name>@<ref>`.

Git tags name entire commits, not directories. A single tag like `v1.0.0` therefore applies to every action in the repository at once. When two actions evolve at different cadences — for example, `setup-node-pnpm` reaches `v2.0.0` while `install-deps` is still on `v1.x` — a flat tag scheme cannot express that without confusing consumers about which action is at which version.

The pattern of sharing GitHub Actions across repositories via a single hosting repo was first encountered while contributing to a previous employer's (https://github.com/Octav-Labs) monorepo.

## Decision

For the initial release of this repository, consumers reference actions with `@main` and no version tags are cut. This keeps the friction low while only two actions exist and every consumer is under the same maintainer.

When the first non-trivial release cycle creates a real need for stable references, this repository will adopt **per-action compound tags** of the form `<action-name>/vMAJOR.MINOR.PATCH`. Consumers then reference an action as:

```
uses: couimet/github-actions/<action-name>@<action-name>/vMAJOR.MINOR.PATCH
```

For example: `uses: couimet/github-actions/setup-node-pnpm@setup-node-pnpm/v1.2.5`.

Each action's tag history is independent. A floating major-version alias (for example `setup-node-pnpm/v1`) may be added later if maintenance overhead stays low.

## Consequences

### Positive

- Each action versions independently; a breaking change in one action does not bump every other action's tag.
- Consumers see both the action and the version in a single `uses:` line, leaving no ambiguity about which release they pinned.
- The current `@main` policy is a deliberate, time-boxed default rather than a long-term commitment.

### Negative

- Compound tag references are longer than plain semver tags; the action name appears twice in the `uses:` line.
- Adopting the scheme later means coordinating tag creation with the first wave of consumer references that move off `@main`.
- Tooling that assumes a single repo-wide tag stream (for example release-please with default configuration) needs per-action configuration before it can drive releases here.

## References

- [GitHub Actions — Using release management for actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/about-custom-actions#using-release-management-for-actions)
- [adr.github.io](https://adr.github.io/) — ADR format used in this repository
