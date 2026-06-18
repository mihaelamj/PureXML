# Common Mistakes to Avoid

Anti-patterns paired with the canonical fix. Mini-DOs are inline; full canonical forms live in `package-swift.md` (closure-with-locals), `testing.md` (test-target placement), and `implementation-patterns.md` (Pattern 6 for fonts).

### ❌ DON'T: Create God Packages

```swift
// WRONG: "Shared" package with everything
Packages/Sources/Shared/
├── Models/
├── Views/
├── Networking/
├── Database/
└── Utilities/
```

✅ **DO:** Split into focused packages
```
Packages/Sources/
├── SharedModels/
├── SharedViews/
├── NetworkClient/
├── DatabaseClient/
└── SharedUtilities/
```

### ❌ DON'T: Circular Dependencies

```swift
// WRONG
AuthFeature depends on AppFeature
AppFeature depends on AuthFeature
```

✅ **DO:** Extract shared code
```swift
AuthFeature depends on SharedAuthModels
AppFeature depends on SharedAuthModels
```

### ❌ DON'T: Inline `deps`, `allProducts`, or `targets` arrays

```swift
// WRONG: inline definitions
let deps: [Package.Dependency] = [
    .package(url: "...", from: "1.10.3"),
    .package(url: "...", from: "1.8.3"),
    // ... dozens more
]

let allProducts: [Product] = [
    .library(name: "ApiShared", targets: ["ApiShared"]),
    .library(name: "ApiClient", targets: ["ApiClient"]),
    // ... many more
]

let targets: [Target] = [
    Target.target(name: "SharedModels", dependencies: []),
    Target.testTarget(name: "SharedModelsTests", dependencies: ["SharedModels"]),
    // ... more inline
]
```

✅ **DO:** closure-with-local-variables pattern, grouped by purpose / layer / platform. Mini-shape for each array:

```swift
// deps
let deps: [Package.Dependency] = {
    // OpenAPI stack
    let openAPIRuntimeDep = Package.Dependency.package(url: "...", from: "1.8.3")
    // Vapor stack
    let vaporDep          = Package.Dependency.package(url: "...", from: "4.119.0")
    return [openAPIRuntimeDep, vaporDep]
}()

// allProducts
let allProducts: [Product] = {
    let apiSharedProduct = Product.singleTargetLibrary("ApiShared")
    let apiClientProduct = Product.singleTargetLibrary("ApiClient")
    return [apiSharedProduct, apiClientProduct]
}()

// targets
let targets: [Target] = {
    // foundation
    let sharedModelsTarget = Target.target(name: "SharedModels", dependencies: [])
    let foundationTargets  = [sharedModelsTarget]
    // api
    let apiClientTarget    = Target.target(name: "ApiClient", dependencies: ["SharedModels"])
    let apiTargets         = [apiClientTarget]
    return foundationTargets + apiTargets
}()
```

Full forms (with platform splits, helper extensions, every dep / product / target spelled out) in `package-swift.md` (Dependencies Definition, Product Definition, Target Organization).

### ❌ DON'T: Skip Test Targets

Every package MUST ship with a matching `Target.testTarget(name: "<name>Tests", dependencies: ["<name>"])`, grouped as a pair with the source target in a named sub-array. See `testing.md > TEST TARGET PLACEMENT` for the canonical form, folder layout, and the rule that mocks live in the test target rather than the source package.

### ❌ DON'T: Transitive Dependencies

```swift
// WRONG: Relying on ApiClient importing SharedModels
import ApiClient
// Using User from SharedModels without importing it
```

✅ **DO:** Explicit imports
```swift
import ApiClient
import SharedModels  // Explicit dependency
```

### ❌ DON'T: Feature-to-Feature Dependencies

```swift
// WRONG: Features depending on each other
let appFeatureTarget = Target.target(
    name: "AppFeature",
    dependencies: [
        "AuthFeature",      // ❌ Feature depending on feature
        "ProfileFeature",   // ❌ Creates tight coupling
    ]
)
```

✅ **DO:** Coordinator pattern or shared protocols
```swift
// Extract navigation/coordination to AppFeature (parent)
// Child features (Auth, Profile) depend on parent's protocols
let authFeatureTarget = Target.target(
    name: "AuthFeature",
    dependencies: [
        "SharedModels",
        "AppCoordination",  // ✅ Protocol package
    ]
)
```

### ❌ DON'T: Use Info.plist for Font Registration in Packages

Three anti-patterns, all covered by `implementation-patterns.md > Pattern 6 (Font/Resource Package)`:

- `UIAppFonts` / `ATSApplicationFontsPath` in Info.plist: doesn't work in SPM packages
- `.copy("Fonts")` in `Package.swift` resources: breaks `Bundle.module` lookup
- `Bundle.main.urls(...)` inside the package: wrong bundle for SPM resources

DO: `.process("Fonts")` in resources, `CTFontManagerRegisterFontsForURL` against `Bundle.module`, called from app init before any UI renders. Full implementation in `implementation-patterns.md > Pattern 6`.

