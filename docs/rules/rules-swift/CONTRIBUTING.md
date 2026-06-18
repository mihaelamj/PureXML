# Contributing

This is the **Swift domain** rule set. The language- and platform-specific craft lives at the repository root; the cross-cutting engineering discipline it builds on is vendored in `core/`.

> **This is the canonical home for the Swift domain rules.** Edit them here. The one exception is `core/`: it is a vendored copy of the shared engineering-discipline spine, so propose changes to those files upstream in the engineering-discipline repo, not in this repo's `core/`.

## Where a change belongs

- **Swift-specific rules** (architecture, concurrency, packages, views, formatting and linting, and so on): propose them here.
- **Cross-cutting discipline** (the engineering ethic, proof discipline, commits, git, testing discipline, and the rest of `core/`): `core/` is a synced copy of the `rules-engineering-discipline` repository. Do not edit it here. Propose those changes upstream so every domain inherits them.

## How to propose a change

1. Open an issue describing the rule and why it generalizes beyond a single project.
2. Keep each rule a single, self-contained document: state the rule, show how to apply it, and give a way to check conformance.
3. A new rule earns its place only by a recurring, transferable need. See `core/self-improve.md` for the threshold.

## The shipped kit

This repository ships drop-in starting configuration: `.gitignore`, `.swiftformat`, `.swiftlint.yml`, and `.githooks/` (a `pre-commit` hook that formats and lints, and a `commit-msg` hook that rejects tool attribution and em dashes). Install the hooks per clone with `git config core.hooksPath .githooks`. Tune the configs to your project, but keep them committed.

## House conventions (this repo follows its own rules)

- **Commits** follow Conventional Commits and `core/commits.md`. Committed text names human contributors only and carries no tool attribution of any kind.
- **No em dashes** in any committed text. Use commas, colons, periods, or restructure.
- **Format and lint** before committing (the pre-commit hook does both); see `formatting-and-linting.md`.
- **Prose** contributions are licensed under CC BY 4.0; any code under MIT. By opening a pull request you agree to license your contribution under those terms.

## Style

Match the existing register: clean prose, a short framing of what the rule governs, concrete DO and DON'T guidance, and an acceptance check the reader can run. No provenance footers, no first person.
