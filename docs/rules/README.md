# PureXML Rules

Load these rules before changing code:

- `code-style.md`
- `namespacing.md`
- `cross-platform.md`
- `testing.md`
- `verification.md`
- `commits.md`
- `research-first.md`

Project-specific overrides:

- PureXML uses a root `Package.swift`.
- Sources live directly under `Sources`.
- Tests live in `Tests` (test target `PureXMLTests`).
- `Package.swift` must keep `dependencies: []`.
- Public API must live under the `PureXML` namespace tree.
- The package must build on macOS, Linux, Windows, and WASI.
- Validation coverage gates: `docs/validation-coverage-registry.txt` (public types),
  `docs/validation-field-registry.txt` (document/subject fields), enforced by
  `scripts/check-validation-coverage.sh` and `scripts/check-validation-fields.sh`.

The broader rule files are retained for detailed guidance. When they include
generic examples, apply the PureXML-specific overrides above.

Canonical Swift rules are vendored at `docs/rules/rules-swift/` and mirrored
from `/Volumes/Code/DeveloperExt/public/rules-swift` (especially
`validation-rules.md`, `parsing-rules.md`, and the `core/` spine). Prefer that
vendored source when root `docs/rules/` copies are missing or have drifted, but
do not let its generic Tiledown examples weaken PureXML's root-package,
dependency-free, Windows, and WASI requirements. PureXML's committed
`.swiftlint.yml` and `.swiftformat` are the coherent project tuning of that
canon: they adopt its opt-in rule set and shared formatter directives, keep
stricter safety (`force_unwrapping`/`force_try`/`force_cast` = error), and
resolve the canon's `--commas always` vs default-`trailing_comma` mismatch by
mandating trailing commas in both tools.
