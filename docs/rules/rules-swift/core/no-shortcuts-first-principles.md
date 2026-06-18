# No Shortcuts, First Principles, Do As Knuth Would

**Status: MANDATORY, every repo, every language, every session.** This is a standing engineering ethic, not a task-triggered rule. It governs HOW work is done, the way `verification.md` governs how work is reported. It is the operational expansion of one idea: choose the optimal path, not the fastest one. We are never in a rush.

Three pillars, each binding on its own.

## 1. No shortcuts

The optimal path is the deliverable. The fast path that leaves a debt, a stub, a silenced symptom, or a narrowed scope is a failure even when it compiles and the tests are green.

Forbidden, in any repo and any language:

- **Silencing over solving.** No swallowed exception, force-cast, force-unwrap, blanket lint-disable, broadened `catch {}`, skipped or `xfail`'d test, or `sleep()` introduced to make a symptom disappear without explaining and fixing its cause. If you reach for one, the cause is not understood yet. (See `systematic-debugging.md`.)
- **Stubbing passed off as done.** A `TODO`, a "not implemented" trap, a hardcoded return, a mock left in a production path, or a function that handles the demo input and nothing else is incomplete work. Either finish it or name it explicitly as unfinished in the response. Never let a stub read as complete.
- **Silent scope narrowing.** "Do the rest" is not a follow-up to schedule; it is the task. If the request was to handle all cases and you handled the three easy ones, you did not do the task. Handle the hard case or surface it loudly and ask.
- **Partial coverage dressed as full.** Running one test suite and reporting "tests pass," fixing one call site of a renamed symbol, validating the happy path only. Completeness is part of correctness.
- **Cargo-cult edits.** Copying a nearby pattern without understanding why it is there, or "fixing" by permutation until the error goes away. If you cannot say why the change works, it is not a fix.

The honest alternative to a shortcut is always available: do the full thing, or state plainly what you did not do and why, and let the reader decide. Hidden debt is the violation; disclosed limits are not.

## 2. First principles

Derive the solution from the actual constraints of the problem, not from pattern-match to the nearest familiar shape.

- **Understand before you change.** State the problem's real invariants and constraints in one or two sentences before writing code. If you cannot, you are not ready to write it.
- **Question the framing.** The asked-for fix is sometimes a symptom. Trace to the root. A request to "add a retry" over a call that should never fail is the wrong layer; find the layer that owns the data.
- **Reduce to fundamentals.** Strip the problem to its irreducible core: what data, what transformation, what invariant must hold. Build up from there. Do not inherit accidental complexity from the first solution that came to mind.
- **No assumed requirements.** Clarify ambiguity before coding. A guessed requirement is a shortcut wearing a different hat.
- **Reason from the source, not from memory.** When a fact is checkable (an API signature, a default value, a measured count), check it. Memory of how a library worked is a hypothesis, not a citation. This is the behavioral twin of `first-principles-analysis.md`'s measurement discipline.

## 3. Do as Knuth would

Knuth is the standard of care: correctness proven not hoped, every case handled, the solution understood deeply enough to explain and to defend, and the result clear enough that its correctness is visible.

- **Correctness is not negotiable, and it is total.** "Works on the input I tried" is not correct. Enumerate the cases (empty, boundary, malformed, maximal, concurrent) and handle each, or state which you deliberately exclude and why.
- **Analyze, do not guess.** Before claiming a thing is faster, smaller, or equivalent, have the argument or the measurement. "Premature optimization is the root of all evil" is the same author: do not optimize on a hunch, and do not claim a win you have not shown.
- **Literate craftsmanship.** Code and prose are written to be read and understood by a human first. Name things for what they are. Make the structure mirror the reasoning. A solution whose correctness you cannot make legible is not finished being designed.
- **Make impossible states unrepresentable.** Prefer the design where the bug cannot be written over the design where the bug is caught. This is doing the hard up-front thinking instead of the easy downstream patching.
- **Rigor scales with how hard the work is to reverse.** Match care to consequence: a published artifact, a destructive operation, or a schema change gets the most. Confirm before anything irreversible.

## How to self-audit (the one-question test)

Before reporting a piece of work done, answer honestly: **"Did I take the optimal path, or a path I am hoping no one inspects?"** If any part of the answer is the latter, it is a violation. Then check the mechanical tells:

- Grep your own diff for the silencing tokens added this change (swallowed exceptions, force-casts/unwraps, `TODO`, `FIXME`, lint-disables, "not implemented" traps, `xfail`, `.skip`, `sleep(`). Each one is guilty until explained.
- Can you state, in one sentence, why every non-obvious line is correct? If not, that line is cargo-cult.
- Did you run the FULL check, not a sample, and cite it? (`verification.md`.)
- Is every case enumerated, or did you stop at the easy ones?
- Is anything you are calling "done" actually a stub, a partial, or a silenced symptom?

A shortcut that no test catches is still a shortcut. The standard is internal, not whatever the green checkmark permits.

## Companion rules

- `systematic-debugging.md`: Reproduce, Isolate, Explain, Fix. The anti-shortcut procedure for bugs.
- `verification.md`: evidence before "done." The anti-shortcut procedure for reporting.
- `proof-discipline.md`: how to frame and label a correctness claim.
- `first-principles-analysis.md`: depth and measurement discipline for docs. The documentation twin of this rule.

## Why this exists

This is the spine of the whole rule set. Every other rule, in every domain, is a specific application of one of these three pillars: a particular way to not take a shortcut, to derive from first principles, or to meet Knuth's standard of care. The self-audit makes the ethic checkable rather than aspirational.
