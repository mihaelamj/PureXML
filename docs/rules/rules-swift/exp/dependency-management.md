# Dependency Management

Unidirectional flow, circular-dependency prevention, and platform-specific dependency separation.

### Unidirectional Flow

```
Foundation (SharedModels, AppColors, AppFont)
    ↓
Design System (AppTheme = AppColors + AppFont)
    ↓
Infrastructure (ApiClient, ApiServer, Middleware, SharedViews)
    ↓
Components (Components [core], SharedComponents, AppComponents)
    ↓
Features (AuthFeature, AppFeature, etc.)
    ↓
Apps (iosApp, macApp)
```

Dependencies only flow downward. NEVER import from a higher layer.

### Circular Dependency Prevention

❌ **DON'T:**
```swift
// AuthFeature → AppFeature
// AppFeature → AuthFeature
// CIRCULAR DEPENDENCY!
```

✅ **DO:**
```swift
// Extract shared code to new package
// Both features depend on: SharedAuthModels
```

### Platform-Specific Dependencies

Separate platform-specific products and targets using `#if os()` conditionals.

#### Products Separation

```swift
// ---------- Base Products (All Platforms) ----------
let baseProducts: [Product] = [
    .singleTargetLibrary("ApiShared"),
    .singleTargetLibrary("ApiClient"),
    .singleTargetLibrary("ApiServer"),
    .singleTargetLibrary("SharedModels"),
    .singleTargetLibrary("OpenAPICachingMiddleware"),
    .executable(name: "apiserverapp", targets: ["ApiServerApp"]),
]

// ---------- Apple-Only Products (iOS + macOS) ----------
#if os(iOS) || os(macOS)
let appleOnlyProducts: [Product] = [
    .singleTargetLibrary("AppTheme"),
    .singleTargetLibrary("SharedViews"),
    .singleTargetLibrary("AuthFeature"),
    .singleTargetLibrary("AppFeature"),
    .singleTargetLibrary("AppFont"),
    .singleTargetLibrary("BetaSettingsFeature"),
    .singleTargetLibrary("DemoAppFeature"),
    .singleTargetLibrary("SharedComponents"),
    .singleTargetLibrary("Components"),
    .singleTargetLibrary("BenefitsComponents"),
    .singleTargetLibrary("AllComponents"),
]
#else
let appleOnlyProducts: [Product] = []
#endif

// ---------- Combine All Products ----------
let allProducts = baseProducts + appleOnlyProducts + [
    .singleTargetLibrary("PlaybookFeature"),  // Always exposed for Xcode scheme visibility
]
```

#### Targets Separation

```swift
let targets: [Target] = {
    // ---------- Base Targets (All Platforms) ----------
    let sharedModelsTarget = Target.target(
        name: "SharedModels",
        dependencies: []
    )
    let apiClientTarget = Target.target(
        name: "ApiClient",
        dependencies: ["ApiShared", "SharedModels"]
    )
    let baseTargets = [
        sharedModelsTarget,
        apiClientTarget,
    ]

    // ---------- Apple-Only Targets (iOS + macOS) ----------
    #if os(iOS) || os(macOS)
    let appColorsTarget = Target.target(
        name: "AppColors",
        dependencies: []  // Foundation: zero dependencies
    )
    let appThemeTarget = Target.target(
        name: "AppTheme",
        dependencies: [
            "AppColors",  // Design system combines colors + fonts
            "AppFont",
        ]
    )
    let sharedViewsTarget = Target.target(
        name: "SharedViews",
        dependencies: [
            "AppColors",
            "AppFont",
            .product(name: "Inject", package: "Inject"),
        ]
    )
    let authFeatureTarget = Target.target(
        name: "AuthFeature",
        dependencies: ["SharedModels", "SharedViews", "AppColors", "AppFont"]
    )
    let appleTargets = [
        appColorsTarget,
        appThemeTarget,
        sharedViewsTarget,
        authFeatureTarget,
    ]
    #else
    let appleTargets: [Target] = []
    #endif

    // ---------- PlaybookFeature (Always Defined, Conditionally Linked) ----------
    let playbookTarget = Target.target(
        name: "PlaybookFeature",
        dependencies: [
            "Components",
            "AppComponents",
            "SharedModels",
            "ApiClient",
            .product(name: "Inject", package: "Inject"),
            .product(
                name: "Playbook",
                package: "playbook-ios",
                condition: .when(platforms: [.iOS])  // ← Platform-specific dependency
            ),
            .product(
                name: "PlaybookUI",
                package: "playbook-ios",
                condition: .when(platforms: [.iOS])
            ),
        ]
    )

    return baseTargets + appleTargets + [playbookTarget]
}()
```

#### Why Separate Platforms?

**Benefits:**
- ✅ Server targets build on Linux CI without Apple SDKs
- ✅ UI targets only compile on Apple platforms
- ✅ Clear separation between backend and frontend code
- ✅ Prevents accidental dependencies on Apple frameworks in server code
- ✅ Faster CI builds (Linux can skip UI packages)

**When to Use:**
- UI components, SwiftUI views → `#if os(iOS) || os(macOS)`
- Shared models, API contracts → No conditional (base products)
- Server code, Vapor endpoints → No conditional (base products)
- Apple-only frameworks (UIKit, AppKit) → `#if os(iOS) || os(macOS)`

**Use `#if os()` for platform detection in `Package.swift`, never `#if canImport(UIKit)`.** `#if canImport` is evaluated lazily and silently breaks the manifest on Linux CI; `#if os()` is evaluated at manifest-parse time and gives deterministic builds across all platforms. This is the most common SPM landmine on cross-platform packages.

