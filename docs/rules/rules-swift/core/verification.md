# Verification Before Completion

**Status: applies to every completion claim, in any language or discipline.**

Never claim work is complete, fixed, or passing without fresh evidence from the relevant verification command. Every completion claim must be backed by command output captured in the same response. The same discipline applies whether the work is code, a written document, or a data transformation: the claim "it's done" is only as good as the check you ran and quoted.

## Core rules

### Rule 1: No claim without fresh evidence

Run the verification command in the same response where you make the claim.
- MUST run the command, not assume it from earlier output
- MUST quote the relevant lines (exit code, failure count, error summary)
- MUST NOT extrapolate ("the lint passed earlier so the build should pass")
- MUST NOT use phrases like "should pass", "looks good", "I believe it works"

### Rule 2: Match the command to the claim

Every claim has a command that decides it. Run that command, not a proxy for it.

| Claim | Required check | What to confirm |
|---|---|---|
| "Build succeeds" | the project's build command | exit 0, no errors |
| "Tests pass" | the test runner (or a targeted filter) | 0 failures, expected count of tests ran |
| "Lint clean" | the linter with the project config | 0 errors (warnings reported separately) |
| "Format clean" | the formatter in check/lint mode | exit 0, no diffs |
| "Bug fixed" | the test or input that reproduced the bug | now passes; state which one |
| "Refactor preserved behavior" | the full test suite | 0 failures |
| "Numbers are correct" | the script that produces the numbers | values match what the doc/report states |
| "Document builds / links resolve" | the doc build or link checker | exit 0, no broken references |

If you do not have the required command, state that explicitly. Do not guess.

### Rule 3: Failure reporting

Report partial results honestly.
- MUST list which checks were run, which passed, which failed, which were skipped
- MUST NOT bundle a partial run under a "done" headline
- MUST quote the first 3 to 5 errors verbatim if any check failed

### Rule 4: Pre-commit gate

Run the project's full local gate, in its defined order, before claiming a change is commit-ready: format, then lint, then build, then test (whichever of these the project defines). Cite each step's outcome. Git hooks may run a subset; that is not a substitute for explicit citation in the response.

### Rule 5: Boundary of "done"

**Done means**: the change is staged, the gate's commands have output that confirms success, and any user-visible behavior the change affects has been exercised (a UI smoke for screen changes, an integration check for engine/API changes, a re-measurement for a documented number, etc.).

**Not done**: the typecheck succeeded, the code looks right, tests "should" pass, "ready to commit" without running the gate.

## Mechanical enforcement: local and CI

Every gate a machine can decide should run in two places: a local git hook, so a violation is never committed, and CI, so a violation is never merged even if the local hook was skipped. The local hook catches it early; CI is the backstop.

A typical split:

| Gate | Local hook | CI job |
|---|---|---|
| Commit-message style | `commit-msg` | `style` |
| File-content style | `pre-commit` | `style` |
| Structural/naming rules | `pre-push` | `style` |
| Format clean | `pre-push` | `build` |
| Lint clean | `pre-push` | `build` |
| Build and tests pass | `pre-push` | `build`/`test` |

Enable the local hooks once after cloning, per the project's hook setup (for example, pointing the hooks path at the tracked hooks directory). A gate that exists only in CI still lets a broken commit land locally; a gate that exists only locally is skipped the moment someone bypasses the hook. Both layers, or neither claim is safe.

## Anti-patterns

- "All set" with no command output in the response
- "Tests pass" while the run was partial (a single-suite filter while another suite is broken)
- Treating a successful build as proof that tests pass
- Quoting old output from earlier in the conversation as if it were fresh
- Marking a task item complete before running the gate

## Why this exists

A green checkmark in your memory is not evidence; a fresh command in this response is. The gap between "I changed the code so it should work" and "I ran the check and here is the output" is exactly where regressions ship. Citing the command and its result makes the claim auditable by the reader instead of trusted on faith, and it forces the author to actually run the thing before saying it's done.
