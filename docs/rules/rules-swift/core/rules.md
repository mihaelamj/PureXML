# Authoring Rule Files for an AI Coding Agent (MANDATORY)

**Status: MANDATORY whenever you create, edit, split, merge, or deprecate a rule
file.** A rule file is an instruction an AI coding agent will read and obey under
load, with partial context, and without the chance to ask you what you meant. Its
job is to change the agent's behavior reliably. A rule that is vague, untestable,
or self-contradictory does not do that job; it adds tokens and noise while
changing nothing. This is the meta-rule: how to write the rules. It is a specific
application of `no-shortcuts-first-principles.md` (a rule with no acceptance check
is a stub passed off as done) and the authoring twin of `self-improve.md`, which
governs *when* a correction earns a rule at all.

## What a good rule is

A rule is **a behavior the agent must change, stated so an outside reader can check
whether it did.** Three properties, each non-negotiable:

- **Imperative and unambiguous.** Use MUST / MUST NOT / NEVER / ALWAYS for binding
  clauses, SHOULD for strong defaults, MAY for genuine options. "Try to write good
  code," "follow best practices," "be consistent" are not rules; they are wishes.
  Replace each with the specific, checkable behavior it gestures at.
- **Testable.** Every binding clause must be verifiable by someone other than its
  author, ideally by a command. If you cannot describe how to catch a violation,
  you cannot tell whether the rule is being followed, and neither can the agent.
- **Non-contradictory and scoped.** A rule must not fight another rule. When two
  rules seem to conflict, the fix is almost always scope: name the condition under
  which each applies, so exactly one governs any given case.

## Structure of a rule file

State the contract first, the mechanism second, the proof last. A rule file
should read top to bottom as: *what the rule is → how to apply it → how to confirm
it was applied.*

1. **Title + status line.** One line naming the rule and its binding strength:
   when it applies (always / on a named trigger), and what it governs. If your
   tooling reads frontmatter (a `description`, file-glob, always-apply flag),
   include it; if it does not, an opening status sentence carries the same load.
2. **Opening paragraph.** One or two sentences: the primary objective and why it
   matters. The reader should know after this paragraph whether the rule applies
   to their task.
3. **The rule itself.** The binding clauses, grouped by topic, general before
   specific. Plain-prose framing, then bulleted MUST/MUST NOT clauses. Number or
   name rules consistently so they can be cited (`§2`, "the silent-mismatch
   clause").
4. **Patterns and anti-patterns.** Show the correct shape and the tempting wrong
   shape side by side. A WRONG/RIGHT pair teaches faster than either alone, and
   the agent pattern-matches on examples as much as on prose.
5. **Acceptance check.** The command(s) or procedure that prove conformance. This
   is the most important section and the most often skipped. See below.
6. **Companion rules.** Cross-references to the rules this one specializes,
   complements, or depends on, so a reader lands in the right neighborhood.
7. **Why this exists.** A short paragraph on the failure that motivated the rule.
   This is what lets a future reader judge whether the rule still earns its place.

Not every rule needs every section. A three-line rule does not get a decision tree.
But the spine, *state → apply → prove*, is mandatory regardless of length.

## When a rule is MANDATORY (and when it is not)

Binding strength is a claim; do not inflate it.

- **MANDATORY / MUST** is for behavior whose violation is a defect: it produces
  wrong output, hidden debt, an irreversible mistake, or a broken invariant.
  Reserve the strongest language for these. If everything is MANDATORY, nothing is.
- **SHOULD** is a strong default with named exceptions. Use it when the right
  behavior is clear but a justified deviation exists. Name when the exception
  applies.
- **MAY** is a real option with no preference. Use it sparingly; most "MAY"s are
  actually a SHOULD with the condition left implicit.
- **Always-on vs. triggered.** An always-on rule is read every session and costs
  tokens every session; spend that budget only on rules that genuinely apply
  broadly. A triggered rule names its trigger precisely ("when adding a network
  call," "when the change touches a schema") so it loads only when relevant.

## The acceptance check is the rule

A rule the agent can claim to follow without any way to catch a lie is not a rule;
it is a suggestion. **Every binding rule ships a way to verify conformance**, and
the strongest form is a command whose output decides the question.

- Prefer a **runnable check**: a grep that MUST return empty, a linter invocation
  that MUST pass, a test that MUST be green, a build that MUST succeed. State the
  expected result (exit code, empty output, count) so there is no interpretation.
- Where no command exists, ship a **checklist** of observable conditions, each
  phrased so two reviewers would agree on pass/fail.
- The check belongs **in the rule file**, next to the clause it proves, not in a
  reviewer's head. A rule whose acceptance lives only in prose ("be thorough") has
  no acceptance.
- Reading the rule is necessary but not sufficient. If a rule ships an acceptance
  command and a session skipped it, that session did not follow the rule. Executing
  the check is the act of compliance, not citing the prose.

Example of the shape (the specifics belong to each rule):

```
## Acceptance check
Conforms when: `grep -rn 'TODO\|FIXME' src/` returns no lines added by this
change; the linter exits 0; and every new public symbol has a doc comment
(spot-check or a doc-coverage command). A change that adds a silenced symptom
fails this check even if the suite is green.
```

## Examples carry as much weight as prose

The agent learns the rule from the example at least as much as from the clause.

- **Pair WRONG with RIGHT.** Show the anti-pattern and the fix together. The
  contrast is the lesson.
- **Make examples concrete and self-contained.** A generic example the reader
  cannot map to a real case teaches nothing. Use a realistic snippet, name real
  types, show the actual command.
- **Keep examples honest.** An example that would not actually pass the rule's own
  acceptance check is worse than no example. Verify your examples against the rule.

## DO

- State binding strength explicitly and accurately; reserve MUST/NEVER for real
  defects.
- Make every binding clause testable, and ship the test (command or checklist) in
  the file.
- Open with the objective so a reader can decide relevance in one paragraph.
- Pair anti-patterns with corrected patterns; keep both concrete.
- Scope rules so none contradicts another; resolve apparent conflicts by naming
  conditions.
- Cross-reference companion rules so the reader lands in the right neighborhood.
- Name the failure that motivated the rule, so its continued relevance is judgeable.

## DON'T

- Do not write a vague rule ("be consistent," "use best practices"); it changes no
  behavior and costs tokens.
- Do not ship a rule with no way to verify conformance; an unprovable rule is a
  suggestion.
- Do not inflate binding strength; if everything is MANDATORY, the word is noise.
- Do not let two rules contradict; do not paper over the conflict with prose,
  scope them.
- Do not write an example you have not checked against the rule's own acceptance.
- Do not bury the acceptance check in someone's head; it belongs in the file.

## Acceptance check

A rule file conforms when: (1) it opens with a status/binding line and an
objective paragraph a reader can act on; (2) every binding clause uses precise
modal language (MUST / MUST NOT / SHOULD / MAY) and is individually testable;
(3) it ships an acceptance check, a runnable command with a stated expected result
where one is possible, otherwise an observable checklist, located in the file next
to what it proves; (4) at least one WRONG/RIGHT example pair appears for any
non-obvious clause, and each example would itself pass the rule; (5) no clause
contradicts another rule, or the conflict is resolved by explicit scope; and (6)
it names the failure that motivated it. A "rule" that is only aspirational prose
with no test, or whose every clause is MANDATORY, or whose examples were never
checked, fails this meta-rule even though it is syntactically a rule file.

## Companion rules

- `self-improve.md`: when a recurring correction earns a rule in the first place,
  and the thresholds that gate rule creation. This file governs *how* to write the
  rule that file decides to create.
- `no-shortcuts-first-principles.md`: the ethic this specializes. A rule with no
  acceptance check is a stub passed off as done; disclosed limits are fine, hidden
  gaps are the violation.
- `proof-discipline.md`: the model for acceptance checks that decompose a claim
  into separately provable parts with explicit status labels.

## Why this exists

Rules that read well but cannot be checked drift silently: the agent claims
conformance, no command contradicts it, and the gap surfaces only as a defect
later. The fix is to make every rule carry its own proof of compliance, so
following the rule and verifying the rule are the same act. A rule set whose rules
are testable improves under its own weight; one whose rules are aspirational
accumulates noise. Portable to any rule set for any AI coding agent.
