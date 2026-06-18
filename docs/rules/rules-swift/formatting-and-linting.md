# Formatting and Linting

**Status: MANDATORY.** Two tools enforce a consistent surface: SwiftFormat applies a deterministic format, SwiftLint flags style and correctness smells. Both run before every commit through a pre-commit hook, and again in CI. The point is that no unformatted or unlinted code reaches the history, and no contributor has to argue about style in review: the config decides, the hook enforces.

## The rules

1. **Config is checked in and is the source of truth.** `.swiftformat` and `.swiftlint.yml` live at the repository root and are committed. Formatting and lint behavior come from those files, never from per-editor settings, so every clone and CI run produces the identical result.
2. **Run both before every commit.**
   - Format: `swiftformat . --config .swiftformat`
   - Lint: `swiftlint --config .swiftlint.yml --strict`
   Run format first (it resolves some lint findings on its own), then lint. `--strict` makes warnings fail, so a warning cannot accumulate into noise that hides the next real one.
3. **A pre-commit hook runs both, on staged Swift files, every commit.** Install it per clone: hooks live in `.git/` and are not cloned, so either ship a tracked `.githooks/pre-commit` and set `git config core.hooksPath .githooks`, or use the pre-commit framework (https://pre-commit.com) with the committed `.pre-commit-config.yaml` (`pre-commit install`, plus `pre-commit install --hook-type commit-msg` for the message checks). The hook formats and lints the staged set and refuses the commit on any failure.
4. **CI is the backstop.** Because hooks are not cloned, CI re-runs both as a required gate: `swiftformat --lint . --config .swiftformat` (lint mode fails on unformatted code rather than rewriting it) and `swiftlint --config .swiftlint.yml --strict`. A clone that never installed the hook still cannot merge unformatted or unlinted code.
5. **No silent disables.** A `// swiftlint:disable` is a shortcut (see `core/no-shortcuts-first-principles.md`). Every disable carries a one-line reason and is scoped as tightly as possible (`// swiftlint:disable:next <rule>` over a single line, not a file-wide disable). A disable with no justification is a violation.

This is a different hook from the commit-message hook in `core/git-discipline.md`: the pre-commit hook checks file content (format and lint); the commit-msg hook checks the message text (no tool attribution, no em dashes). Install both.

## Acceptance check

A conforming repo has: (1) `.swiftformat` and `.swiftlint.yml` committed at the root; (2) a tracked pre-commit hook (a `.githooks/` entry plus `core.hooksPath`, or a committed pre-commit config) that runs SwiftFormat and SwiftLint on staged Swift files and blocks the commit on failure; (3) CI steps that run `swiftformat --lint` and `swiftlint --strict` as required checks; (4) no `// swiftlint:disable` without an adjacent reason, verified by a grep. A repo that relies on contributors remembering to format, with no hook and no CI gate, fails this rule.

## Companion rules

- `core/no-shortcuts-first-principles.md`: a blanket lint-disable to silence a warning is the shortcut this rule forbids.
- `core/git-discipline.md`: the commit-message hook (attribution and em-dash checks) is the other half of the commit-time enforcement.
- `code-style.md`: the conventions that the formatter and linter mechanize.
