# Validation Rules (MANDATORY)

When validating any parsed model (a config, a document, a manifest, a feature
model, any structured value), you **MUST** follow the **OpenAPIKit validation
idiom** by [Matt Polzin](https://github.com/mattpolzin/OpenAPIKit). This is the
companion to `parsing-rules.md`: parse first, validate second, and write the
validation layer the way OpenAPIKit does. This is not a suggestion. Validations
are composable values, never imperative if-trees.

## Reference repository

**https://github.com/mattpolzin/OpenAPIKit** (local mirror:
`PureYAMLResearch/References/OpenAPIKit`). Study `Sources/OpenAPIKit/Validator/`:
`Validation.swift`, `Validator.swift`, `Validator+Convenience.swift`,
`Validation+Builtins.swift`, `ReferenceValidations.swift`, and the tests under
`Tests/OpenAPIKitTests/Validator/`. Last re-analysed against upstream main
`1d42ea6477` (2026-06-11); when in doubt, the live source wins over this
summary.

## The philosophy (the eleven principles you must honor)

1. **Parse, then validate, as two passes.** The types make many illegal states
   unrepresentable; the validator catches only what the type system cannot or
   should not enforce. Validation runs over an already parsed, well typed value.
2. **Validations are composable values, not if-trees.** A validation is a plain
   struct of closures (a description, a check, an apply-predicate). You combine
   them with an algebra (`&&`, `||`, `all`, `lift`, `unwrap`, `lookup`). You
   declare what correct looks like; you do not hand write traversal or
   accumulation loops.
3. **The description states the CORRECT state, never the failure.** Phrase every
   description positively ("Operations contain at least one response"). The
   framework derives the negative message by prefixing `"Failed to satisfy: "`.
   One source of truth, two readings.
4. **Errors carry a context path.** An error is a reason plus a location (the
   coding path). The path is filled in by the traversal and rendered
   consistently ("at root of document", "at path: .a.b['c']"). Failures are
   locatable without manual bookkeeping.
5. **Application is predicate gated.** Every validation has a `when:` predicate
   (default true) that runs before the check, with the full context, so a rule
   scopes itself to a subset of values, a coding-path position, or a document
   version without conditionals inside the check body.
6. **Dispatch is type directed.** A `Validation<Subject>` applies only to values
   of type `Subject`, anywhere they appear in the tree, because the erased
   wrapper filters by runtime type. You pick the subject type; the framework
   finds every instance.
7. **Default set plus custom extension.** Ship a curated default validator and a
   blank one. Builders are fluent and chainable (`.validating(...)`,
   `.withoutValidating(...)`), returning Self. Users compose policy from defaults
   plus or minus their own rules. Builtins live as `public static var` members of
   a dedicated caseless namespace enum (`BuiltinValidation`), referenceable by
   KeyPath rooted at that namespace so they can be added or removed by identity,
   and the identity key IS the description string (`withoutValidating` removes by
   matching descriptions across every list), so descriptions must be unique and
   stable. Where strictness comes in grades, model the grades as whole-set
   replacement methods on the validator (OpenAPIKit's lenient reference checks
   by default, `validatingAllReferencesFoundInComponents()` swapping in the
   strict set, `skippingReferenceValidations()` clearing it), not as flags
   threaded through individual rules.
8. **Single-error and multi-error forms.** The Bool form (frontload the
   description, return false if invalid) is for a rule that fails one way and auto
   formats the message. The array-of-errors form is for a rule that can fail in
   several places at once (one error per missing variable, per undefined
   reference), each with its own reason and path. Choose by whether a single value
   can fail in more than one way.
9. **Two error channels with a strict switch.** Validation errors always throw;
   parse warnings are separate and elevated to errors only under `strict: true`
   (the default), otherwise returned for inspection. Keep "spec violation" and
   "lossy but parseable" distinct.
10. **One framework, parameterized over the document.** When more than one layer
    validates (an authoring linter over a hand-written manifest, a semantic
    validator over a resolved model), do NOT copy the machinery per layer.
    OpenAPIKit fixes the document type to `OpenAPI.Document`; you generalize it.
    Factor the error type, `Validation`, the erased wrapper, the `Validator`, and
    the combinators into one framework in the lowest layer, parameterized over both
    the `Subject` and the `Document` (the cross-cutting context: a library, a scope,
    or `Void` when a rule needs nothing beyond its subject). Each layer then defines
    only its own document, its rules, and its traversal. Two copies of
    `ValidationError` is the same duplication this rule exists to prevent, one level
    up.

11. **Each rule lives in exactly one authoritative layer; lower layers do not
    re-implement it.** A rule belongs to the layer that holds the data it judges. A
    *semantic* rule, one that needs a resolved model (referential closure, scope,
    inheritance, readiness), lives in the semantic layer and nowhere else. A lower
    layer, a syntax or source-structural validator, checks only what is meaningful at
    its own level (an empty identifier, a duplicate authored name) and MUST NOT copy
    the semantic rules down, even when it could approximate them. The reason is the
    dependency arrow: if the semantic layer depends on the syntax layer (parse then
    resolve), the syntax layer cannot call back into the semantic one without a cycle,
    so the temptation is to re-derive the semantic rule in the lower layer, and that
    is the duplication to refuse. The correct direction is the other way: the
    authoritative (higher) layer *consumes* the lower one (it parses, then validates),
    so the full "source to semantic verdict" path lives at the top, not split into two
    drifting rule sets. When you find the same check in two layers, delete the copy in
    the layer that does not own the data, and document the boundary on both sides.

## The core types (build these, with these exact roles)

- **`ValidationContext<Subject>`**: the read-only bundle every check receives.
  Carries `document` (the whole structure, for cross-cutting checks), `subject`
  (the current value of the specialized type), and `codingPath` (where in the
  tree). Adapt `document` to your root model name.
- **`Validation<Subject>`**: the atomic value. Stores `description: String`, a
  multi-error `validate: (ValidationContext<Subject>) -> [ValidationError]`, and a
  `predicate: (ValidationContext<Subject>) -> Bool`. Has `apply(to:at:in:)` that
  gates on the predicate then runs validate. Two inits:
  - multi-error: `init(description: String? = nil, check: @escaping (Context) -> [ValidationError], when: @escaping (Context) -> Bool = { _ in true })`.
  - single-error Bool: `init(description: String, check: @escaping (Context) -> Bool, when: ... = { _ in true })`, where false yields one error `"Failed to satisfy: \(description)"`. Description is REQUIRED here because it is the message.
- **`ValidationError`**: `reason: String` plus `codingPath: [CodingKey]`. Its
  `description` strips a trailing period from the reason, renders an empty path as
  `"<reason> at root of document"` and a non-empty path as
  `"<reason> at path: <path>"`. Match this formatting.
- **`ValidationErrorCollection`**: the one value thrown at the end, with `.values:
  [ValidationError]`. Tests inspect `.values`.
- **`Validatable`**: a pure marker protocol constraining `Subject`. Conform your
  model types (and the primitives/containers you traverse) to it.
- **`AnyValidation`** (type erasure, internal): wraps `Validation<T>` so a
  heterogeneous list lives together, and filters by runtime type. It MUST guard
  against an optional matching its wrapped type (a `T?` must not satisfy a
  `Validation<T>`): cast with `as? T`, then also check `type(of: subject) == type(of: input)`.
- **`Validator`**: a `final class` (reference semantics; the fluent builders
  mutate self and return it, `@discardableResult`). Holds the default rules in
  TWO tiers (`nonReferenceDefaultValidations` + `referenceDefaultValidations`)
  plus `customValidations`; the effective order is fixed and tested:
  non-reference defaults, then reference defaults, then custom. Exposes `init()`
  (defaults on), a `blank` with none, fluent `validating(...)` /
  `withoutValidating(...)`, and a `validationDescriptions` accessor listing the
  active rules. The builtin add/remove overloads take VARIADIC KeyPaths via
  parameter packs (`validating<each T: Encodable>(_ validations: repeat
  KeyPath<BuiltinValidation.Type, Validation<each T>>)`), so one call can mix
  builtins specialised on different subject types.
- **`BuiltinValidation`**: the caseless namespace enum carrying every shipped
  rule as a `public static var ...: Validation<Subject>`. Rule FAMILIES that
  differ only by type are generated by an internal factory (OpenAPIKit's
  `References.referencesAreValid(ofType:named:mustBeInternal:mustPointToComponents:)`
  computes graded descriptions and checks per component type) rather than
  copy-pasted per type.

## How validation runs

Traverse the parsed model and offer every value to every validation; the type
filter in the erased wrapper makes each `Validation<T>` fire only on `T` values,
at every path where one occurs. OpenAPIKit does this by walking an `Encodable`
through a fake `Encoder` that, at each node, applies validations and extends the
coding path by the key or index. Dictionary keys are themselves validated: the
keyed container's child encoder recovers the original key value (`AnyCodingKey
.originalValue as? Validatable`) and offers it to the validations too. You may
reuse that Encoder trick when your model is `Encodable`, or write an explicit
recursive walk that builds the path and dispatches by subject type. Either way:
predicate gates before check, errors accumulate with their path, and the whole
run throws a single `ValidationErrorCollection` if non-empty.

The warning channel rides the same traversal: types declare their parse-time
warnings via small protocols (`HasWarnings`, and `HasConditionalWarnings` for
warnings that depend on the whole document), the walker collects them at each
node and contextualises each with the coding path where it was found. The
entrypoint is `validate(using:strict:) -> [Warning]` (`@discardableResult`):
under `strict: true` (the default) warnings are converted into
`ValidationError`s and merged into the thrown collection; under `strict: false`
they are returned for inspection instead.

## Authoring a validation (every surface)

- **Multi-error init**: return your own `[ValidationError]`, one per problem, each
  with a custom reason and `context.codingPath`. Use when a value can fail several
  ways at once.
- **Single-error Bool init**: pass a positive `description` and a Bool check;
  failure auto-produces `"Failed to satisfy: <description>"`. The dominant form.
- **`.validating(...)` on the Validator**: add a rule inline without constructing
  a `Validation` (closure form, Bool form, prebuilt form, and a KeyPath form that
  adds named builtins). Mirror these overloads.
- **`lift(\.child, into: validationsOnChild...)`**: run child-typed validations
  against a lifted value while keeping the parent's path and document. The key
  compositional move.

Real exemplar (single-error, KeyPath check):

```swift
public static var operationsContainResponses: Validation<Operation> {
    .init(
        description: "Operations contain at least one response",
        check: \.responses.count > 0
    )
}
```

Real exemplar (multi-error, one error per offender):

```swift
public static var serverVariablesAreDefined: Validation<Server> {
    .init(
        description: "All server template variables are defined",
        check: { context in
            context.subject.urlTemplate.variables
                .filter { !context.subject.variables.contains(key: $0) }
                .map { name in
                    ValidationError(
                        reason: "Server Object does not define the variable '\(name)' ...",
                        at: context.codingPath
                    )
                }
        }
    )
}
```

## The combinator algebra (the declarative core)

Provide these as free functions returning closures, so they compose by value:

- **`&&` / `||`** on error-array checks (`&&` concatenates both error lists; `||`
  short-circuits, errors only if both fail) and on Bool predicates (the obvious
  way).
- **`==`, `!=`, `>`, `>=`, `<`, `<=`** lifting a `KeyPath<ValidationContext<T>, U>`
  or a `KeyPath<T, U>` (rooted through `context.subject`) and a literal into a
  predicate. The dual rooting lets an author write `\.subject.foo`, `\.document.bar`,
  or `\SomeType.foo` interchangeably and thereby tell the type system which type the
  validation specializes on.
- **`take(\.path) { value in Bool }`**: dig to a value and run arbitrary logic
  beyond equality.
- **`lift(\.child, into:)`**: as above.
- **`unwrap(\.optional, into:description:)`**: unwrap an optional, error if nil,
  else run child validations.
- **`lookup` / `unwrapAndLookup`**: resolve a reference against the document's
  component store, error if not found, else validate the resolved value.
- **`all(validations...)`**: apply many `Validation<T>` to the same context
  (equivalent to `lift` with `\.self`).

Usage reads declaratively: `check: \.responseOutcomes.count >= 1 && { $0.subject.responseOutcomes.allSatisfy { $0.status == 200 } }`,
or `check: take(\.tags) { tags in tags.map(\.name).count == tags?.count }`.

One type-inference contract to honour between the two clauses: the subject type
must be pinned in at least one of `check:` / `when:`. When one clause only
touches `\.document` or `\.codingPath` (which say nothing about the subject),
the other clause must name the subject type, for example via a fully rooted
KeyPath (`take(\OpenAPI.Document.servers) { ... }`), so the compiler knows what
the validation specialises on. Both `take` and every comparison operator come
in two rootings for exactly this reason (`KeyPath<Subject, U>` and
`KeyPath<ValidationContext<Subject>, U>`).

## The test style (MANDATORY, copy it exactly)

Tests mirror the philosophy. The recipe:

1. **Build the subject** (the document / model), seeding the values under test.
2. **Build a validator**: `Validator.blank.validating(...)` to test ONE rule in
   isolation, `Validator()` to test the default set, or `Validator().validating(...)`
   for a custom rule on top of defaults.
3. **Run**: `try model.validate(using: validator)` (success tests simply run; a
   throw fails the test).
4. **Assert failures** with `XCTAssertThrowsError`, cast to
   `ValidationErrorCollection`, then check `.values.count`, each
   `.values[i].reason` (including the `"Failed to satisfy: "` prefix), and
   `.codingPath.map { $0.stringValue }`. For message rendering, assert
   `String(describing: error)` equals `"<reason> at path: <path>"`.
5. **Isolate the combinators**: test each operator/`lift`/`take` as a pure
   function against a hand-built dummy context, asserting `.isEmpty` / `.count` of
   the resulting closure, with no full traversal. Test the erased wrapper directly
   (`apply(to:at:in:)`), including that an optional and a wrong type both yield no
   errors, and that the same value of the same type twice yields two errors.

Representative failure test to copy:

```swift
func test_unconditionalServerCountCheckFails() {
    let document = ... // seed two server arrays
    let validator = Validator.blank
        .validating("All server arrays have more than 1 server", check: \[Server].count > 1)
    XCTAssertThrowsError(try document.validate(using: validator)) { error in
        let error = error as? ValidationErrorCollection
        XCTAssertEqual(error?.values.count, 1)
        XCTAssertEqual(error?.values.first?.reason, "Failed to satisfy: All server arrays have more than 1 server")
        XCTAssertEqual(error?.values.first?.codingPath.map { $0.stringValue }, ["paths", "/hello/world", "get", "servers"])
    }
}
```

(Use Swift Testing `#expect` where the project uses Swift Testing, but keep the
same shape: run the validator, assert the collection's count, each reason, each
path.)

## Exhaustive testing (MANDATORY, the upstream bar)

The recipe above applied to a SAMPLE of rules does not satisfy this rule. The
upstream suite is exhaustive in five specific ways, and a conforming repo
reproduces all five:

1. **Every rule ships a failing AND a succeeding test**, the upstream
   `test_X_fails` / `test_X_succeeds` pairing (BuiltinValidationTests covers
   every builtin both ways). The succeeding fixture is a NEAR MISS, the boundary
   the rule almost trips (the value at the exact limit, the predicate one step
   from firing), not merely an unrelated clean document. A rule with only its
   failing direction tested is untested: nothing proves it stays quiet on valid
   input.
2. **A configuration-pin test** asserts the EXACT ordered
   `validationDescriptions` list (and count) of every validator configuration:
   `blank` is empty, each fluent variant lists precisely its rules, the full
   default set is pinned description by description (upstream
   `test_variousConfigurationsHaveExpectedValidationCounts`). Adding, removing,
   or rewording a rule MUST fail a test before the change is deliberate.
3. **The machinery has its own negative tests** (upstream ValidationTests):
   the erased wrapper applied to an Optional subject yields no errors; applied
   to a wrong type yields no errors; a false `when` predicate yields no errors;
   a conditional rule gets a dedicated does-not-run test
   (`test_validationNeverRunsAndSucceeds`); and the same value of the same type
   occurring twice yields two errors (the positive control proving the
   negatives are not vacuous).
4. **Many-error documents assert the COMPLETE error list**: exact
   `.values.count`, then every reason and every coding path, in traversal order
   (upstream asserts all nine reference errors with all nine paths in one
   test). `contains` on a single element hides regressions in every other
   error and in the ordering.
5. **Coverage is itself a tested law.** Keep a registry of every finding the
   default set can produce (stable codes, or the descriptions list where codes
   do not exist) and a meta-test that one failing fixture and one near-miss
   fixture exist per entry, asserting set equality and naming any gap in the
   failure message. Plant a fake entry once to prove the meta-test fails, then
   remove it. Upstream pins this via the exact descriptions list; a registry
   plus meta-test is the equivalent for code-bearing findings.

## Full validation coverage (MANDATORY)

The exhaustive-testing section proves every *rule* is tested. This proves the
rule *set* is complete over the input model: no field goes unexamined. The
OpenAPIKit idiom validates the whole document structure, not a chosen subset; a
conforming repo does the same.

1. **Every field is modeled or reported, never silently ignored.** For each
   field or construct the input can carry, the parsed model either handles it (it
   has a typed home and the validations that constrain it) or the validator emits
   an explicit "unsupported" / "ignored, with reason" finding. A field that is
   neither handled nor reported is a silent gap and a violation, even when the
   output looks right. This is the `…FieldsAreModeledOrReported` discipline: layer,
   transform, shape, style, mask, matte, and silent-risk fields each get a rule
   that accounts for every key.
2. **Unknown and unexpected fields are detected, not dropped.** A rule asserts
   that every key present is either known (modeled) or explicitly permitted
   metadata, and reports an unrecognized key with its path. The parser must not
   `try?`-swallow or otherwise discard a field the validator should have seen
   (see `core/no-shortcuts-first-principles.md`: silent drop is forbidden).
3. **Behavior-affecting fields get priority and a silent-risk rule.** Any field
   that can change output but is easy to miss (a compositing mode, a matte source,
   a time remap) carries a dedicated rule so its presence is never accepted
   unhandled.
4. **Coverage over the model is a tested law.** Keep a registry of every field or
   construct the input model defines, and a meta-test asserting each maps to a
   validation or an explicit unsupported/ignored classification. Adding a field to
   the model without classifying it MUST fail that meta-test. This is the
   input-side twin of the finding-coverage meta-test above: that one proves every
   rule is exercised; this one proves every field has a rule.

A validator can pass every test it ships and still be incomplete if a field of
the input was never given a rule. Full coverage closes that gap: the validation
set is complete with respect to the input model, and incompleteness is caught
mechanically, not by review.

## Every public type is validated or excluded (MANDATORY)

This is the part it is most important to stick to. Validation is not applied to a
chosen subset of types. It is applied to EVERY public type. A package's public
surface is the set of values other code can construct and hand in, and each one
is a place malformed or untrusted state can enter, so each public type is exactly
one of two things:

- **validated**: it has at least one `Validation<Subject>` that constrains it, or
- **excluded**: it is listed in a checked-in exclusions file with a one-line
  reason (a pure data-transfer type with no invariants, or a type whose
  invariants are already made unrepresentable by its initializer).

There is no third option. A public type that is neither validated nor excluded
with a reason is a silent gap, and a silent gap is a violation even when every
shipped test passes.

**Enforce it mechanically, per repo, not by review.** Ship a coverage gate (a
script run by the pre-commit hook and in CI) that: (1) enumerates every public
type in the package, (2) checks each against the validator's subject types and
the exclusions file, and (3) fails the build, naming the type, if any public type
is neither covered nor excluded. Adding a new public type without a validation or
an exclusion entry MUST fail the gate. That is what "stick to it" means: the
discipline is enforced by the build, every time, for every public type.

**Prefer make-unrepresentable over validate.** The strongest coverage is deleting
the rule. If a type can carry its own invariant (a non-empty collection type, a
smart constructor that rejects the bad value at init), the bad state cannot be
constructed and needs no runtime validation. Excluding such a type because its
invariants are unrepresentable is the win, not a loophole. Reach for a
`Validation` only when the type system cannot or should not carry the invariant.

## DO

- Separate parsing from validation; validate an already typed value.
- Write each rule as a `Validation<Subject>` value with a positive description.
- Build errors as reason plus context path; let the traversal fill the path.
- Use the single-error Bool form by default; the multi-error form when a value can
  fail several ways at once.
- Gate scope with the `when:` predicate, not with `if` inside the check.
- Compose with the operator algebra (`&&`, `lift`, `take`, `unwrap`, `lookup`,
  `all`) instead of nesting conditionals.
- Ship a default validator plus a blank one; make rules addable and removable by
  identity.
- In tests, isolate one rule with `.blank.validating(...)`, assert the error
  collection's count, reasons, and coding paths, and unit test the combinators as
  pure functions.
- When a second layer needs validation, reuse one framework parameterized over the
  document (principle 10); never copy the error type, `Validation`, or `Validator`.

## DON'T

- Do not fold validation into parsing.
- Do not write a monolithic `validate()` that appends to a mutable error array
  through a tree of `if` statements. That is the anti-pattern this rule exists to
  replace.
- Do not phrase descriptions as failures; phrase the correct state.
- Do not drop the location; every error carries its path.
- Do not let an optional satisfy a non-optional validation (guard the erasure).

## Acceptance check

A repo whose validation conforms to this rule satisfies all of: (1) validations
are declared as `Validation<Subject>` values (grep finds the type, not a single
imperative `func validate()` accumulating into a `var errors`); (2) descriptions
read as the correct state, are unique (they are the removal identity), and
failures render `"Failed to satisfy: ..."`; (3) errors carry a coding path and
render `"... at path: ..."`; (4) a `Validator` with a default set and a `blank`,
plus fluent `validating` / `withoutValidating`; (5) tests build the subject, run
`validate(using:)`, and assert the thrown collection's `.values` count, reasons,
and coding paths, with the combinators unit tested as pure functions; (6) every
public entry point that consumes untrusted input gates on the validator before
doing work, and a non-throwing recovery accessor (a `validationOutcome` style
API returning valid-or-errors) exists beside the throwing gate for callers that
inspect rather than abort; (7) the test suite is exhaustive per the section
above: a failing plus near-miss succeeding pair for every rule, a
configuration-pin test over exact validation descriptions, machinery negatives
(optional, wrong type, false predicate, does-not-run), complete error-list
assertions on many-error documents, and a coverage meta-test (or descriptions
pin) that names any rule shipped without its fixtures; (8) the validation set is
complete over the input model per the full-coverage section: every field is
modeled or explicitly reported, unknown keys are detected, and a coverage
meta-test fails if any field of the model lacks a rule. A validator that is one
big if-tree fails this rule even if it produces correct results, and so does a
validator that quietly ignores fields the input can carry.
