# Writing Plans for Multi-Step Work

For any change spanning multiple modules, multiple commits, or multiple sessions, write an implementation plan after the design is approved (see `brainstorming.md`) and before touching code. The plan turns the design into ordered, verifiable tasks.

## Core rules

### Rule 1: When a plan is required

Write a plan when:

- The change touches two or more modules or packages.
- The change spans two or more commits to land safely.
- The change has ordering constraints (e.g., "regenerate the API before updating callers").
- The change is expected to take more than a single working session.
- The change is a migration with a fallback or rollback path.

**MAY skip** when the design itself was already a one-module, one-commit shape.

### Rule 2: Plan structure

Include, in this order:

```markdown
# <feature>: <short title>

**Goal:** <one sentence from the approved design>
**Approved design:** <link or paste the 30-second design>

## File map

| Path | Change | Notes |
|---|---|---|
| src/foo/Bar.<ext>     | new  | holds the BarClient interface |
| src/app/AppEntry.<ext> | edit | wire BarClientLive into the dependency container |
| ...                   | ...  | ... |

## Tasks (ordered)

### T1. <verb> <object>
**Files:** src/foo/Bar.<ext>
**Does:** <what>
**Verifies:** build the Foo module
**Commit:** feat(foo): introduce BarClient interface

### T2. ...

## Constraints

- Layer order: Foo MUST NOT import any higher-level module
- The API is regenerated as part of T3, before T4 starts
- ...

## Test plan

- T1 unit tests live alongside the Foo module
- T4 integration test exercises the full chain with the injected double
- The pre-commit verification gate runs on each task

## Done definition

- All tasks committed
- Formatter and linter clean across touched modules
- Full build green
- Full test suite green
- Changelog / commit messages convey the externally visible story
```

### Rule 3: Tasks are independently verifiable

- Each task ends in a runnable verification command (build, run a test filter, lint a file).
- Each task ends in a commit with `<type>(<scope>): summary`.
- Tasks are ordered by dependency, not by author convenience.
- A task that cannot be verified on its own should be merged into the next one.

### Rule 4: Plans are living documents

Update the plan when reality diverges:

- Discovered a missing file: add a task; do not silently widen an existing task.
- Found that two tasks merge: collapse them with a note.
- Hit an unforeseen dependency: stop, surface it, re-approve before continuing.

The plan in the repo MUST match what the implementation actually did. Stale plans are worse than no plan.

### Rule 5: Save location

Default: `docs/plans/YYYY-MM-DD-<feature-slug>.md` in the repo where the work happens. Override only if the project's conventions specify a different location.

## Anti-patterns

- Writing the plan AFTER starting implementation.
- Tasks that say "implement everything for module X" with no breakdown.
- Tasks with no verification command.
- Plans without a file map (you cannot verify scope without one).
- Treating the design and the plan as the same thing (the design is "what and why"; the plan is "in what order, with what proofs").
- Bundling unrelated cleanup into a feature plan (separate plans per concern).
