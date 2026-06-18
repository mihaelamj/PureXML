# When a Correction Earns a Rule (MANDATORY)

**Status: MANDATORY whenever a correction, bug, or review note recurs.** A rule
set is only as good as its discipline about what enters it. Two failures are
symmetric and equally costly: leaving a recurring mistake uncodified, so it keeps
happening, and promoting a one-off into a permanent rule, so the set bloats with
noise that costs tokens every session and changes nothing. This rule sets the
thresholds: when a pattern has recurred enough to deserve a rule, and when it has
not. It is the upstream companion to `rules.md`, which governs *how* to write the
rule once this file says one is warranted.

## The core question

Before adding or updating a rule, answer: **has this corrected itself by being
told once, or does it keep coming back?** A rule is justified only by recurrence
or by stakes high enough that a single occurrence is one too many. A thing fixed
correctly the first time it was raised does not need a rule; it needs the fix.

## Thresholds for creating a rule

Treat these as the bar, not a ceiling. Meeting one is sufficient grounds to draft
a rule; meeting none means the correction stays a correction.

- **Recurring pattern (≥3 occurrences).** The same shape of code, the same kind of
  fix, or the same structural choice appears across **three or more files or
  sessions**. Three is the signal that it is a pattern and not a coincidence.
  Extract it into a rule with a concrete example drawn from the real cases.
- **Repeated mistake (≥2 occurrences).** The same error or its near-twin is made,
  caught, and corrected **twice**. The second time is the evidence that telling it
  once did not stick; write the rule so the third time is caught by a check instead
  of a person.
- **Repeated review note (≥3 mentions).** The same feedback is given in reviews
  **three or more times**. Recurring human review effort is exactly the cost a rule
  exists to eliminate; promote it.
- **Measured win (>20% on a real resource).** An optimization or approach that
  saves more than a fifth of a measured resource (time, memory, tokens, build) on
  a real workload, with the measurement recorded, earns a rule so the win is not
  re-discovered each time.

## Stakes override the count

Some things get a rule on the **first** occurrence, because the cost of the second
is unacceptable. Recurrence is not required when:

- A **security or data-loss vulnerability** is discovered. One is enough.
- A change introduces a **breaking change with wide blast radius** (many files or
  consumers affected). Codify the migration path immediately.
- A **new library, framework, or major dependency is adopted.** Its conventions
  and gotchas become a rule at adoption, before the patterns scatter.
- A **compliance or correctness invariant** is introduced that must hold
  everywhere. Make it a rule the moment it is known, not after it is first violated.

In these cases the threshold is one, and the rule is written the same session the
need is recognized.

## What does NOT earn a rule

The symmetric failure is over-codification. Resist a rule when:

- It happened **once** and the single correction resolved it, with no sign of
  recurrence and no high-stakes reason to pre-empt a second.
- It is a **personal stylistic preference** with no defect behind it. Style with no
  correctness or cost consequence is configuration, not a rule.
- It is **already covered** by an existing rule. The fix is to sharpen or
  cross-reference that rule, not to add a second one that will drift out of sync
  with the first.
- It is **so specific** that it will apply exactly once more, ever. A rule that
  fires on a single future case is a comment in the wrong place.

When in doubt, record the correction (a note, a memory, a commit message) and wait
for the recurrence that promotes it. An uncodified note costs nothing; a premature
rule costs tokens every session it is loaded.

## Updating beats adding

The default when a pattern recurs near an existing rule is to **strengthen that
rule, not spawn a new one.** Adding overlapping rules splits the truth across two
files that will disagree the next time one is edited.

- **Better example found.** Replace the rule's example with the clearer real case.
- **New edge case discovered.** Add a clause or a note to the owning rule; do not
  start a sibling.
- **Dependency or API changed.** Revise the affected rule in the same session the
  change lands, so its examples and clauses do not go stale.
- **Two rules converging on one topic.** Merge them, keep the cross-references, and
  delete the weaker. Fewer, sharper rules beat many overlapping ones.

## Deprecating a rule

A rule that no longer earns its tokens is removed deliberately, not deleted on a
whim and not left to rot.

1. **Mark it deprecated** in place, with the reason and any replacement.
2. **Provide the migration path** to the rule or behavior that supersedes it.
3. **Update dependents** that cross-reference it before removal.
4. **Remove it** once nothing points at it. A rule no longer used, no longer
   accurate, or fully absorbed by another is dead weight; cut it.

## Keep the set lean

The rule set is read under load; every always-on rule is a recurring tax. Review
periodically for: rules no longer used, examples gone stale against current code,
clauses now covered better elsewhere, and pairs that should be merged. The goal is
the **smallest set of testable rules that prevents the recurring failures**, not
the largest set of plausible advice.

## DO

- Promote a pattern to a rule at ≥3 occurrences across files or sessions; promote a
  repeated mistake at ≥2; promote repeated review feedback at ≥3.
- Promote on the first occurrence when stakes are high (security, data loss, wide
  breaking change, new dependency, correctness invariant).
- Strengthen or merge an existing rule before adding a new one on the same topic.
- Record one-off corrections as notes and wait for the recurrence that earns a rule.
- Deprecate with a migration path; remove only after dependents are updated.

## DON'T

- Do not codify a one-off that the single correction already fixed, absent a
  high-stakes reason.
- Do not turn a bare stylistic preference into a rule; that is configuration.
- Do not add a rule that overlaps an existing one; sharpen the existing one instead.
- Do not write a rule so specific it will fire exactly once more.
- Do not let deprecated or stale rules linger; they tax every session that loads
  them.

## Acceptance check

A rule addition conforms when: (1) it cites the recurrence that justified it (the
files, sessions, or reviews where the pattern appeared) **or** names the high-stakes
reason that overrides the count; (2) a search confirms no existing rule already
covers the same ground, or the existing rule was strengthened instead; (3) the new
or updated rule itself meets `rules.md` (testable clauses, acceptance check, honest
example); and (4) any rule it supersedes is deprecated with a migration path, not
left to drift. A rule introduced on a single low-stakes occurrence, or one that
duplicates an existing rule, fails this check even if the rule's text is well
written.

## Companion rules

- `rules.md`: how to write the rule this file decides is warranted, testable
  clauses, acceptance checks, honest examples, accurate binding strength.
- `no-shortcuts-first-principles.md`: the ethic behind leanness, the smallest
  correct set, not the largest plausible one; disclosed limits over hidden bloat.
- `proof-discipline.md`: the standard a new rule's own acceptance check should meet.

## Why this exists

A rule set decays in two opposite directions, and both hurt. Under-codify, and the
same mistake recurs because the correction never became a check. Over-codify, and
the set fills with one-off advice that costs tokens every session while preventing
nothing, and the signal drowns. Explicit thresholds (recurrence counts for ordinary
patterns, a count of one for high stakes) keep the set growing only where growth
pays, and a deprecation path keeps it shrinking where it no longer does. Portable to
any rule set for any AI coding agent.
