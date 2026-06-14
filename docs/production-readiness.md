# Production readiness standard (read this every iteration)

PureXML is going into an IDE as the authority on whether a developer's XML and
XSD is correct. The bar is not "passes our test suite." It is correctness,
total and characterized, with the false-positive direction held at zero. Read
this before and after every schema-validity (or any conformance) iteration and
hold the change to it.

## The four stoppers (each one blocks production on its own)

1. **Rejecting valid input (false positives).** The tool must never reject a
   correct schema or document. `valid-schemas-rejected` (#148) and
   `valid-instances-rejected` (#146) must reach 0. In an editing loop the first
   wrong red mark on work the developer knows is correct destroys trust in every
   other diagnostic, and they disable the validator. This is the worst-felt
   failure and the one to guard hardest: under-rejection is recoverable,
   over-rejection is a non-starter.

2. **Silently accepting faulty input (false negatives).** `invalid-schemas-accepted`
   (#145) and `invalid-instances-accepted` (#147) must reach 0. The tool exists
   to catch the developer's mistakes; a missed error behind a green light ships
   broken work, and a false negative the user cannot see is worse than a crash.

3. **Uncharacterized correctness.** Every count is measured against one finite
   corpus (the XSTS subset). Real XML and XSD are unbounded. "Passes the suite"
   is not "is correct." Production needs a differential harness against a trusted
   reference validator over a large real-world corpus, plus fuzzing for hangs and
   crashes. And no silent debt: every case the implementation excludes must be
   named and bounded, never a "documented under-rejection" that emits nothing.

4. **Interactive safety.** An IDE revalidates on keystrokes against possibly
   hostile input. There must be a proven worst-case time and memory bound (a cap
   is a band-aid, not a bound), every diagnostic must be located (line and
   column), and validation must be recoverable (report all errors, not the
   first).

## Per-iteration checklist (apply on EVERY change)

- Does this change reject any valid input? If yes, that is a false positive:
  stop and fix before merge. The valid-rejected buckets (#146, #148) may never
  rise, and their target is 0, not "held at a baseline."
- Does it leave a silent gap? If it under-rejects, the exclusion must be NAMED
  and bounded in code and changelog, and tracked as debt to close, never shipped
  silently.
- Is it verified against the XSTS differential AND an adversarial over-rejection
  critic before merge?
- Are any new diagnostics located (line/col) and recoverable?
- Is it durable: committed, fast-forward merged, pushed to the remote, and the
  memory mirror committed and pushed? "Merged locally" is not done.

## Definition of done (the whole goal, not one iteration)

All four buckets at 0 on the FULL XSTS (not the subset); a differential + fuzz
harness so correctness is bounded, not sampled; every diagnostic located and
recoverable; a proven resource bound so interactive use cannot hang; and every
deliverable durable. Until at least false positives are 0, PureXML is a strong
engine but not an authority to put in front of a developer.
