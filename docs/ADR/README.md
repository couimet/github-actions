# Architecture Decision Records (ADR)

This directory contains architectural decision records documenting the "why" behind major design choices in `couimet/github-actions`.

## What are ADRs?

Architecture Decision Records capture important architectural decisions along with their context and consequences. They help:

- **Onboard new contributors** — understand why things are the way they are
- **Prevent re-litigation** — avoid revisiting decisions already made
- **Document trade-offs** — preserve the reasoning behind choices

## Format

We follow the format from [adr.github.io](https://adr.github.io/):

- **Status:** Proposed / Accepted / Deprecated / Superseded
- **Context:** What's the situation and problem?
- **Decision:** What did we decide to do?
- **Consequences:** What are the trade-offs and implications?

## ADRs

| #                                           | Title                     | Status   |
| ------------------------------------------- | ------------------------- | -------- |
| [0001](./0001-monorepo-tagging-strategy.md) | Monorepo Tagging Strategy | Proposed |

## Future ADRs

Decisions we may document as the repository grows:

- Scope policy for new actions (when does a pattern earn its own composite action?)
- Test coverage requirements for new actions
- SHA-pinning policy for third-party action references
