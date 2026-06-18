# Business Rules and Constraints (the starting artifact)

**Status: MANDATORY, the first artifact of any app.** Before the domain model,
before any renderer, the starting point is a clear, explicit definition of the
**business rules** and the **constraints** that bound them. You cannot formalize a
domain you have not defined, and you cannot defer the renderer (see
`domain-first.md`) until you know what the app must do and what limits it operates
under. This artifact is the input the domain and engine are built from.

## The two halves

### 1. The business rules

What the system must do, must guarantee, and must never allow, stated as explicit,
checkable statements, not as prose that sounds agreed but means something different
to each reader. "An order with no line items cannot be submitted" is a rule; "we
validate orders carefully" is not. Each rule names the correct state, in the
positive, the same way a `Validation<Subject>` does (see `validation-rules.md`).
These statements become the domain invariants, the documented effect of each
engine intent, and the validations on every public surface type. A rule you cannot
state as a checkable sentence is a rule you have not finished defining.

### 2. The constraints (the limitations), each defined up front

The business rules do not float free; they run inside limits that shape the domain.
Name each as early as it is known; a constraint you cannot yet pin down is recorded
as an explicit open risk, never silently deferred until it surfaces mid-build:

- **External services.** Which REST services (and other I/O) the app depends on,
  and their contracts: endpoints, request and response payloads, status and error
  modes, idempotency, pagination, rate limits. Each external service becomes a
  data-layer port the engine reaches only through an injected, interface-segregated
  seam (see `dependency-injection.md`); where the contract is an OpenAPI document,
  generate the types and client from it (see `openapi-generated.md`). An undefined
  service contract is an undefined data layer.
- **Compliance.** The regulatory and data-handling requirements the app is bound by:
  data retention and residency, PII and consent, audit trails, and any
  jurisdiction-specific rule. These are not features to add later; they harden into
  domain invariants and validations that the build proves, and they constrain what
  state is even representable.
- **Auth.** The authentication and authorization model, defined, not assumed.
  *Authorization* (who may do what) shapes the read capability slices and the
  enabled or disabled surface flags the engine computes, and it gates which intents
  are permitted. *Authentication* (how identity is proven, how a session is held
  and refreshed) shapes the data-layer seams and the session surface state. Leaving
  auth implicit produces an app that is permissive by accident.

## Why this is the starting point, not a later pass

Each constraint determines the shape of the domain and the engine: a REST contract
defines a port, a compliance requirement defines an invariant, an authorization
rule defines which intents exist and when they are enabled. Define them first and
the domain is built to fit. Discover them late and you retrofit them through code
already written, threading auth through call sites that assumed none and bolting
compliance onto state that was never designed to carry it, which is the expensive,
error-prone path this rule exists to avoid. The clarity is also what makes the
domain formalizable at all: explicit rules and named limits are the structure the
rest of the discipline (validation as values, round-trip laws, proof discipline)
operates on.

## DO

- Write the business rules as explicit, positive, checkable statements before
  modeling the domain; each becomes an invariant, an intent effect, or a validation.
- Enumerate the external services and their contracts up front; turn each into a
  data-layer port, and generate from the OpenAPI document where one exists.
- Define the compliance requirements and the auth model (authentication and
  authorization) as first-class constraints, before any feature is built on top.

## DON'T

- Do not start from vague intentions ("validate carefully," "secure the app"); a
  rule that is not a checkable sentence is not yet defined.
- Do not begin building against an unnamed service contract, an unstated compliance
  requirement, or an assumed auth model; name them first.
- Do not treat auth or compliance as a later hardening pass; retrofitting them
  through written code is the failure this rule prevents.

## Acceptance check

A conforming project has, before its domain is modeled: (1) the business rules
written as explicit, positive, checkable statements, each traceable to an invariant,
an intent effect, or a validation; (2) every external service named with its
contract, each mapped to a data-layer port (generated from its OpenAPI document
where one exists); (3) the compliance requirements stated and expressed as
invariants or validations the build proves; and (4) the authentication and
authorization model defined, with authorization gating intents and capability
slices and authentication shaping the session seams. A project that begins coding
against undefined rules, an unnamed service contract, unstated compliance, or an
implicit auth model fails this rule even if it compiles.

## Companion rules

- `domain-first.md`: this artifact is what you start from; the renderer is deferred
  until it is defined.
- `ui/pre-ui-layer.md`: the business rules become the engine's intent effects and
  the domain invariants; the constraints become the data-layer ports.
- `validation-rules.md`: rules and constraints expressed as composable
  `Validation<Subject>` values; every public type validated or excluded with a
  reason.
- `openapi-generated.md`: the REST service contracts as generated types and clients.
- `dependency-injection.md`: each external service reached only through an injected
  protocol seam.
