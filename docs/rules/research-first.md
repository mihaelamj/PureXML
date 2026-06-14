# Research first (when stuck, read the source and the literature)

PureXML reimplements, in pure Swift, behavior that mature C/Java/C#/Python
libraries already get right. When a spec point is ambiguous, an algorithm is
unclear, a test disagrees with your reasoning, or you are about to guess: stop
and consult sources before writing code. Guessing at a standard's corner case is
how this engine accrues silent bugs. Reading the reference is how it stops.

This is mandatory, in order:

1. **Look in the research repo first.** The private `PureXML-research` repo
   vendors reference implementations and analysis for exactly this purpose:
   `libraries/` (libxml2, Xerces-J, Xerces-C, .NET `System.Xml.Schema`, Python
   `xmlschema`, and others), `notes/` (prior clean-room write-ups), and the W3C
   conformance suites. Find the matching routine and read it. The authoritative
   algorithm is almost always already on disk. (Example: the MapAndSum
   particle-restriction rule was fixed by reading Xerces `XSConstraints.java`,
   after three incremental guesses had regressed ~30 cases.)

2. **If the needed reference is not there, vendor it.** If no library in
   `PureXML-research/libraries/` covers the area, add one (use the repo's
   `scripts-vendor.sh` / vendoring convention). Pick a permissively licensed,
   widely deployed implementation. Record it in the research repo's attribution.

3. **If what is there is not enough, find more.** One implementation can be
   wrong, stubbed, or lenient (libxml2 stubs particle-restriction; Microsoft and
   Xerces disagree on spec-ambiguous points). When implementations disagree or
   under-specify, gather more of them and compare; the W3C test metadata often
   states which reading is intended.

4. **Always consult the scientific and standards literature.** Read the W3C
   Recommendation text itself (it is the spec, not a library's interpretation),
   its errata, and the academic literature for the underlying algorithm
   (content-model determinism / Glushkov and position automata, Brzozowski
   derivatives, regular-language subset and ambiguity, schema composition). The
   research repo's `references/` and `notes/` collect these; extend them.

## Clean-room discipline (non-negotiable)

The research sources are for **study, not copying**. PureXML stays pure Swift,
dependency-free, Linux- and WASI-compatible (see `AGENTS.md`). Never copy C,
Java, C#, JavaScript, or any non-Swift source into the public package. Extract
the *algorithm and the invariants* from the reference, then implement them from
first principles in Swift. Keep attribution accurate where compatibility work
references a project.

## What counts as "stuck"

Not only a dead end. Any of: a corner case you cannot derive with certainty from
the spec; a conformance test whose expected result contradicts your reasoning;
an occurrence/namespace/derivation rule you are about to special-case by feel; a
choice between two plausible interpretations. In all of these, the reference and
the literature decide, not intuition. Disclose the source you used.
