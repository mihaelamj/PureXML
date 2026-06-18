# Engineering discipline

A domain-agnostic standard of care for building software. These rules govern *how* work is done and *how* it is reported, independent of language, platform, or domain. They are the foundation that the language- and domain-specific rule sets build on.

The premise is simple and demanding: **choose the optimal path, not the fastest one.** Correctness is total, not "works on the input I tried." Claims are proven or measured, never hoped. Bad states are designed out, not patched after. Limits are disclosed, never hidden.

## The rules

| Rule | What it governs |
|---|---|
| `no-shortcuts-first-principles.md` | The core ethic: no shortcuts, derive from first principles, hold to Knuth's standard of care. |
| `proof-discipline.md` | Framing a correctness claim: decompose into provable layers, label each claim's status, treat references as fallible witnesses, name the unproven frontier. |
| `round-trip-transformation.md` | Build a bidirectional transform (parse/print, encode/decode, compile/decompile) as one invertible description; state the round-trip law and prove it, not hope the two directions agree. |
| `first-principles-analysis.md` | Depth target for analysis docs, plus measurement discipline (every number traceable to a command). |
| `verification.md` | No "done" without fresh evidence: run the check, cite the output. |
| `testing-discipline.md` | Real tests on every change; a build is not a test. |
| `systematic-debugging.md` | Reproduce, isolate, explain, then fix. Root cause before patch. |
| `brainstorming.md` | A short design gate before non-trivial implementation. |
| `writing-plans.md` | An ordered, verifiable plan before multi-step work. |
| `commits.md` | Conventional Commits. |
| `file-naming.md` | Lowercase, dashed, ASCII, ISO-dated filenames. |
| `folder-grouping.md` | One folder per unit of work; flatten noise; group siblings. |
| `git-discipline.md` | Issues, labels, branches, PRs, remotes. |
| `rules.md` | How to author rules for an AI coding agent. |
| `self-improve.md` | When a recurring correction should become a rule. |

## How to use these

Point your agent (or yourself) at this directory as always-loaded context. The ethic rules (`no-shortcuts-first-principles`, `proof-discipline`, `verification`, `testing-discipline`) apply on every task. The process rules (`brainstorming`, `writing-plans`, `commits`, `file-naming`) apply when their topic comes up.

## License

Prose under CC BY 4.0, any shipped code under MIT. See `LICENSE.md`.
