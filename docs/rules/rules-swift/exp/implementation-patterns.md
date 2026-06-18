# Implementation Patterns

Six worked patterns for the package layers used in the canonical Swift monorepo. Foundation, Feature, Middleware, API, Component, Font/Resource.

Cross-referenced from elsewhere:
- Aggregator pattern: see Pattern 5 (Component Layer Architecture) > AllComponents Package, the canonical example
- Font registration anti-patterns: see Pattern 6 (Font/Resource Package) > Why This Pattern

### Pattern 1: Foundation Package (No Dependencies)

```swift
// Packages/Sources/SharedModels/Package.swift (excerpt)
let sharedModelsTarget = Target.target(
    name: "SharedModels",
    dependencies: []  // RULE: Foundation packages have ZERO dependencies
)
```

```swift
// Packages/Sources/SharedModels/User.swift
public struct User: Identifiable, Codable, Sendable {
    public let id: UUID
    public let firstName: String
    public let lastName: String
    public let email: String

    public init(id: UUID, firstName: String, lastName: String, email: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
    }
}
```

Foundation packages are pure Swift, no dependencies, highly reusable.

### Pattern 2: Feature Package (Depends on Foundation + Infrastructure)

```swift
// Packages/Sources/AuthFeature/Package.swift (excerpt)
let authFeatureTarget = Target.target(
    name: "AuthFeature",
    dependencies: [
        "SharedModels",      // Foundation: domain models
        "SharedViews",       // Infrastructure: reusable UI
        "AppColors",         // Foundation: colors
        "AppFont",           // Foundation: typography
        "ApiClient",         // Infrastructure: networking
    ]
)
```

```swift
// Packages/Sources/AuthFeature/LoginView.swift
import SwiftUI
import SharedViews
import SharedModels
import AppColors
import AppFont

public struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @Environment(\.appColors) var colors

    public init() {}

    public var body: some View {
        VStack {
            Text("Welcome")
                .bdrFont(.headline)  // From AppFont
                .foregroundColor(colors.primary)  // From AppColors (Apple HIG naming)

            // Use shared components from SharedViews
            // Use models from SharedModels
        }
    }
}
```

Features depend on foundations and infrastructure, never on other features (except parent/child relationships).

### Pattern 3: Middleware Package (Single Purpose Infrastructure)

```swift
// Packages/Sources/OpenAPICachingMiddleware/Package.swift (excerpt)
let apiCachingTarget = Target.target(
    name: "OpenAPICachingMiddleware",
    dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
    ]
)
```

Middleware packages are highly focused, single-purpose, minimal dependencies.

### Pattern 4: API Layer Separation

```swift
// RULE: Separate packages for each API concern

// ApiShared: OpenAPI spec + generated DTOs
let apiSharedTarget = Target.target(
    name: "ApiShared",
    dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
    ],
    plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
    ]
)

// ApiClient: Client-side networking
let apiClientTarget = Target.target(
    name: "ApiClient",
    dependencies: [
        "ApiShared",  // Uses generated DTOs
        "SharedModels",
        "OpenAPICachingMiddleware",
    ]
)

// ApiServer: Server-side handlers
let apiServerTarget = Target.target(
    name: "ApiServer",
    dependencies: [
        "ApiShared",  // Uses generated DTOs
        "SharedModels",
        .product(name: "Vapor", package: "vapor"),
    ]
)

// ApiServerApp: Executable
let apiServerAppTarget = Target.executableTarget(
    name: "ApiServerApp",
    dependencies: ["ApiServer"]
)
```

API layer has 4 packages: Shared (contract), Client, Server, ServerApp (executable).

### Pattern 5: Component Layer Architecture

The component layer has a strict 3-package hierarchy. Start with the Components package first.

#### Component System Architecture

```
Components (core infrastructure)
    ↓
SharedComponents (hot reload)
    ↓
AppComponents (app-specific production components)
```

#### 1. Components Package (CORE - comes FIRST)

**Purpose:** Core component system infrastructure

**Contains:**
- `AnyComponent` - Type-erased component protocol
- `ComponentsBundle` - Bundle management
- `ComponentFactory` - Component instantiation
- `ComponentRegistry` - Global component registration
- `ComponentListComponent` - Component list rendering
- `ComponentRegistrar` - Registration interface
- `SystemComponentRegistrar` - System component registration
- `ComponentListModel` - Component list data model
- `ComponentListView` - Component list view
- `components.json` - Component configuration

**Dependencies:** ZERO (foundation infrastructure)

```swift
// Packages/Package.swift (excerpt)
let componentsTarget = Target.target(
    name: "Components",
    dependencies: [],  // Foundation layer; zero dependencies
    resources: [
        .process("components.json"),
    ]
)
```

**Structure:**
```
Packages/Sources/Components/
├── Protocol/
│   ├── AnyComponent.swift
│   └── ComponentRegistrar.swift
├── Registry/
│   ├── ComponentRegistry.swift
│   ├── ComponentFactory.swift
│   └── SystemComponentRegistrar.swift
├── Bundle/
│   └── ComponentsBundle.swift
├── List/
│   ├── ComponentListModel.swift
│   ├── ComponentListView.swift
│   └── ComponentListComponent.swift
└── components.json
```

#### 2. SharedComponents Package (Hot Reload Infrastructure)

**Purpose:** Hot reload and development-time infrastructure

**Dependencies:**
- Inject (hot reload)
- KZFileWatchers (file watching)

```swift
// Packages/Package.swift (excerpt)
let sharedComponentsTarget = Target.target(
    name: "SharedComponents",
    dependencies: [
        .product(name: "Inject", package: "Inject"),
        .product(name: "KZFileWatchers", package: "KZFileWatchers"),
    ]
)
```

**Purpose:** Enables hot reload of components during development

#### 3. AppComponents Package (App-Specific Components)

**Purpose:** Production app-specific components

**Dependencies:**
- Components (core system)
- AppColors (semantic colors with HSV)
- AppFont (typography)

```swift
// Packages/Package.swift (excerpt)
let appComponentsTarget = Target.target(
    name: "AppComponents",
    dependencies: [
        "Components",  // Core component system
        "AppColors",   // Semantic colors (HSV-based)
        "AppFont",     // App typography
    ],
    resources: [
        .process("Resources"),  // Images, assets
    ]
)
```

**Examples:**
- `BenefitCardComponent` - Benefit display card
- `LanguageSwitcherComponent` - Language selection
- `ButtonComponent` - App-specific buttons

**Structure:**
```
Packages/Sources/AppComponents/
├── BenefitCardComponent.swift
├── LanguageSwitcherComponent.swift
├── ButtonComponent.swift
├── Resources/
│   └── Images/
└── AppComponentsRegistration.swift
```

#### 4. AllComponents Package (Aggregator - Optional)

**Purpose:** Umbrella package for convenient imports.

**This is also the canonical example of the general aggregator pattern.** An aggregator package re-exports its dependencies via `@_exported import`, so a consumer who writes `import YourAggregator` gets everything the aggregator depends on. The same shape works for any umbrella package, not just AllComponents (e.g., a hypothetical `AllFeatures` for a preview app would depend on every `*Feature` package and `@_exported import` each one).

**Dependencies:**
- Components
- AppComponents

```swift
// Packages/Package.swift (excerpt)
let allComponentsTarget = Target.target(
    name: "AllComponents",
    dependencies: [
        "Components",
        "AppComponents",
    ]
)
```

```swift
// Packages/Sources/AllComponents/AllComponents.swift
@_exported import Components
@_exported import AppComponents
```

Use only in preview/demo apps and component libraries, NEVER in production feature paths.

#### Component Layer Rules

Rules:
1. Create the Components package first (core infrastructure).
2. SharedComponents depends only on hot reload tools (Inject, KZFileWatchers).
3. AppComponents depends on Components + AppColors + AppFont
4. NEVER skip the Components package - it contains the core system
5. Component configuration goes in `components.json`
6. All components must conform to the protocol defined in Components
7. Registration happens via ComponentRegistry from Components package

**Order of Creation:**
1. Components (AnyComponent, ComponentRegistry, etc.)
2. SharedComponents (hot reload infrastructure)
3. AppComponents (app-specific components)
4. AllComponents (aggregator - optional)

### Pattern 6: Font/Resource Package

Register fonts using CoreText, not via Info.plist. Resources use `.process()` in Package.swift.

#### Package.swift Configuration

```swift
// Packages/Package.swift (excerpt from targets closure)
let appFontTarget = Target.target(
    name: "AppFont",
    dependencies: [],
    resources: [
        .process("Fonts"),  // .process() registers; .copy() does not
    ]
)
```

Use `.process("Fonts")` to ensure Bundle.module works correctly. NEVER use `.copy()`.

#### Font Registration Implementation

```swift
// Packages/Sources/AppFont/FontRegistration.swift
import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum FontRegistration {
    /// Register custom fonts from the AppFont package
    public static func registerFonts() {
        // Get all resource URLs and filter for .otf files
        guard let resourceURLs = Bundle.module.urls(forResourcesWithExtension: nil, subdirectory: nil) else {
            print("⚠️ No resources found in AppFont bundle")
            return
        }

        let fontURLs = resourceURLs.filter { $0.pathExtension.lowercased() == "otf" }

        guard !fontURLs.isEmpty else {
            print("⚠️ No .otf fonts found in AppFont bundle")
            return
        }

        for url in fontURLs {
            var errorRef: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)

            if !success {
                print("⚠️ Failed to register font: \(url.lastPathComponent)")
                if let error = errorRef?.takeRetainedValue() {
                    print("   Error: \(error)")
                }
            } else {
                print("✅ Registered font: \(url.lastPathComponent)")
            }
        }
    }
}
```

#### Package Directory Structure

```
Packages/Sources/AppFont/
├── FontRegistration.swift       # Registration using CoreText
├── ScaledFont.swift             # Font modifiers (.bdrFont())
└── Fonts/                       # Font resources
    ├── MonitorPro-Normal.otf
    ├── MonitorPro-Bold.otf
    └── MonitorPro-Light.otf
```

#### Usage in App

```swift
// Apps/iosApp/iosAppApp.swift
import SwiftUI
import AppFont

@main
struct iosAppApp: App {
    init() {
        // Register fonts before any UI renders
        FontRegistration.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

#### Why This Pattern?

**Benefits:**
- ✅ Works in SPM packages (Info.plist approach doesn't work in packages)
- ✅ Explicit font registration with error reporting
- ✅ Cross-platform (iOS + macOS) with `#if canImport()` conditionals
- ✅ Uses `Bundle.module` (SPM automatic bundle)
- ✅ Supports multiple font formats (.otf, .ttf) via filter
- ✅ Clear console output showing which fonts loaded

**Why `.process()` not `.copy()`:**
- `.process()` → Resources are processed and accessible via `Bundle.module`
- `.copy()` → Resources copied verbatim, may not work with `Bundle.module`

**Why CoreText not Info.plist:**
- Info.plist font registration only works in app bundles, NOT in SPM packages
- CoreText registration works anywhere (packages, frameworks, apps)

Rules:
1. Use `CTFontManagerRegisterFontsForURL` for font registration.
2. Use `Bundle.module` in SPM packages, not `Bundle.main`.
3. ALWAYS use `.process()` for font resources in Package.swift
4. ALWAYS use `#if canImport(UIKit)` / `#if canImport(AppKit)` for platform imports
5. ALWAYS call `FontRegistration.registerFonts()` in app init BEFORE any UI renders
6. NEVER use Info.plist `UIAppFonts` / `ATSApplicationFontsPath` in packages

