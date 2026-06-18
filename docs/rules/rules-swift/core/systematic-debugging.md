# Systematic Debugging

Find and articulate the root cause of any bug, test failure, or unexpected behavior before proposing or applying a fix. Symptom fixes are forbidden until you can explain why the symptom occurs. This rule is language- and platform-agnostic.

This is the anti-shortcut procedure for bugs, the specialization of `no-shortcuts-first-principles.md` to the moment something is broken: silencing over solving is forbidden, and a fix you cannot explain is a cargo-cult edit.

## Core rules

### Rule 1: Reproduce first, investigate second, fix third

Complete the phases in order.

- Get a deterministic reproduction (a failing test, a sample input, a repro script) before reading code.
- Identify the smallest change that flips the outcome before naming it the cause.
- Do not propose a fix until you can describe the cause in one sentence.

### Rule 2: The four phases

```
1. REPRODUCE
   - capture the exact failing command or input
   - confirm it fails consistently
   - if flaky, treat the flake as the primary bug (the race is the cause)

2. ISOLATE
   - bisect: which component, which file, which line
   - for tests: shrink to the smallest failing assertion
   - for crashes: get the full stack trace with line numbers

3. EXPLAIN
   - state the root cause in one sentence
   - identify the invariant that was violated or the assumption that was wrong
   - if you cannot explain it, you have not found the cause yet

4. FIX
   - the smallest change that addresses the cause, not the symptom
   - add or update a test that would have caught it
   - re-run the suite and cite the result (see testing-discipline.md)
```

### Rule 3: Common pitfalls to check first

Consider these before deeper investigation. They are the recurring shapes a root cause tends to take, independent of language:

- **Null / absent value**: trace where a value that should exist became absent, rather than guarding the read site.
- **Concurrency**: was the failing code on the expected thread, task, or execution context? Look for shared mutable state, ordering assumptions, and missing synchronization.
- **Dependency wiring**: did the failing path receive the dependency it expected, or did a default / live implementation leak in where a test double was intended?
- **State and lifetime**: a value read before it was set, after it was freed, or from a stale copy.
- **Type / contract mismatch**: a fix that "looks right" but the compiler or runtime rejects is often hiding a wrong assumption about the contract.
- **Cache or stale build**: rebuild from clean if behavior contradicts the visible source.

### Rule 4: Banned behaviors during debugging

Do not:

- Apply a fix to make the test pass without understanding why it was failing.
- Wrap the failing call in an error-swallowing construct to silence the symptom.
- Add a synchronization or context annotation to "fix" a concurrency error without confirming the call site needed it.
- Disable, skip, or mark the failing test expected-to-fail and move on.
- Insert a sleep or retry to mask a timing bug whose race you have not explained.
- Attempt multiple fixes in parallel hoping one sticks.

If a fix does not hold, return to phase 2 (Isolate). Do not stack guesses.

### Rule 5: Reporting

State, in this order, when reporting on a debugging session:

1. The reproduction (command or input + expected vs actual).
2. The root cause (one sentence).
3. The fix (what changed and why it addresses the cause, not the symptom).
4. The verification (which test now passes that did not before, with counts).

## Anti-patterns

- "I think it might be X, let me try" applied to multiple guesses in series.
- Adding logging without a hypothesis to test.
- Reading the whole file looking for "something off" instead of bisecting.
- Calling a flake "transient" without finding the race.
- Declaring a fix complete because the failing test now passes, without checking why the others still pass.

## Companion rules

- `no-shortcuts-first-principles.md`: the ethic this specializes. Silencing a symptom instead of fixing its cause is the canonical shortcut; if you reach for one, the cause is not understood yet.
- `testing-discipline.md`: the fix is not done until a test that would have caught the bug exists and the suite is re-run with cited counts.
- `proof-discipline.md`: how to frame and label what the fix proves versus what remains open.
