# Testing Patterns (Architecture Angle)

ExtremePackaging-specific testing concerns: per-package test target, cross-package test doubles. Full Swift Testing rules live in `testing.md` (the top-level rule). Both files state the per-package-test-target rule, by deliberate cross-context dual-homing.

Full Swift Testing rules live in `testing.md`. Two ExtremePackaging-specific points:

**Per-package test target.** Every source target ships with a matching test target. Run a single package in isolation:

```bash
cd Packages
swift test --filter <PackageName>Tests
```

Folder layout: `Packages/Sources/<Package>/` and `Packages/Tests/<Package>Tests/`.

**Cross-package test doubles.** Mocks live in the test target, not the source package. Public protocols can be defined in the source package; their mock implementations stay in `Packages/Tests/<Package>Tests/Mocks/`. Never publish mocks from `Sources/` (they leak into production binaries).

```swift
// Packages/Sources/ApiClient/APIClientProtocol.swift
public protocol APIClientProtocol {
    func login(email: String, password: String) async throws -> User
}

// Packages/Tests/ApiClientTests/Mocks/MockAPIClient.swift
public struct MockAPIClient: APIClientProtocol { /* ... */ }
```

