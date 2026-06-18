# Brainstorming Before Code

For any new feature, refactor, or change scoped beyond the trivial (as a rough heuristic, anything touching more than a couple of files, or more than one module or package), present a design and get approval before writing implementation code, scaffolding files, or running generators. Quick fixes (one file, an obvious diff, no new public surface) are exempt.

## Core rules

### Rule 1: The design gate

Present a design and pause for approval before implementation.

A design covers, at minimum:

- **Goal**: one sentence.
- **Touched files / modules**: an explicit list with what changes in each.
- **Public surface**: any new types, interfaces, exported signatures, or API the change introduces.
- **Dependency direction**: confirm the change does not violate the project's layering or module-boundary rules.
- **Tests**: which existing tests cover this; which new tests are needed.
- **Migration / compatibility**: anything callers must change.
- **Risks / open questions**: at least one, even if minor.

### Rule 2: Scope of the gate

Apply the gate when:

- A new module, package, or build target is being added.
- A public type or interface is being introduced.
- A user-facing screen, view, or top-level component is being added or replaced.
- A change crosses an architectural layer or module boundary.
- An API contract or schema definition is being modified.
- A migration touches data, schema, or persistence.

**MAY skip** when:

- Single file, obvious diff, no new public surface.
- A pure rename or extract that the requester already specified.
- A bug fix where the fix is forced by a failing test.

When in doubt, present the design. The cost of pausing is low.

### Rule 3: How to present

Keep the design short enough to read in about 30 seconds.

```
Goal: <one line>

Files:
- src/foo/Bar.<ext>          (new, holds the BarClient interface)
- src/foo/BarClientLive.<ext> (new, real implementation)
- src/foo/BarClientFake.<ext> (new, test/preview double)

Public surface:
- interface BarClient { fetch(...) -> Bar }
- error type BarError { ... }

Dependencies: standard library only. No upward imports.

Tests:
- BarClientTests covers fetch happy path, decode error, network error.
- Injects the fake double.

Risks:
- Decoding from snake_case input: confirm whether a code generator is in
  play here, or if this is a hand-rolled client.

OK to proceed?
```

### Rule 4: Banned pre-approval actions

**MUST NOT**, before approval:

- Run a project initializer or any code generator.
- Create new files (other than scratch design notes).
- Edit existing source files.
- Run schema or API regeneration.
- Stage or commit anything.
- Spawn implementation subagents.

You MAY, before approval:

- Read the codebase to inform the design.
- Run searches to identify touched files.
- Run a build to confirm the current baseline compiles.

### Rule 5: After approval

Approval is for the SCOPE PRESENTED. If the implementation reveals a hidden case that changes scope:

- Stop.
- Surface the divergence.
- Get fresh approval before continuing.

Do not silently expand scope to "while I am here, I also fixed X."

## When approval is skipped

If a direct implementation command arrives without a design (e.g., "just add the new endpoint"), do the design pass anyway as a short, five-bullet message and ask once:
"OK to proceed with this, or do you want changes?"

A single confirmation is enough; no full ceremony required.

## Anti-patterns

- Jumping into code on a "small" change that turns into eight files touched.
- Presenting code as the design ("here is the diff, looks good?").
- Burying the design in a long preamble before the actual question.
- Designing in isolation without reading the existing patterns first.
- Treating silence as approval.
