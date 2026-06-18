# Package.swift Patterns

The closure-with-local-variables pattern for the three top-level arrays in `Package.swift`: `deps`, `allProducts`, `targets`.

All top-level `Package.swift` arrays (`deps`, `allProducts`, `targets`) use the closure-with-local-variables pattern.

### Dependencies Definition

```swift
// ---------- Dependencies ----------
let deps: [Package.Dependency] = {
    // Apple's OpenAPI stack
    let openAPIGeneratorDep = Package.Dependency.package(
        url: "https://github.com/apple/swift-openapi-generator",
        from: "1.10.3"
    )
    let openAPIRuntimeDep = Package.Dependency.package(
        url: "https://github.com/apple/swift-openapi-runtime",
        from: "1.8.3"
    )
    let openAPIVaporDep = Package.Dependency.package(
        url: "https://github.com/swift-server/swift-openapi-vapor",
        from: "1.0.1"
    )

    // Vapor stack
    let vaporDep = Package.Dependency.package(
        url: "https://github.com/vapor/vapor",
        from: "4.119.0"
    )
    let fluentDep = Package.Dependency.package(
        url: "https://github.com/vapor/fluent",
        from: "4.13.0"
    )
    let fluentSQLiteDep = Package.Dependency.package(
        url: "https://github.com/vapor/fluent-sqlite-driver",
        from: "4.8.1"
    )

    // Custom middlewares
    let loggingMiddlewareDep = Package.Dependency.package(
        url: "https://github.com/mihaelamj/OpenAPILoggingMiddleware",
        from: "1.1.0"
    )
    let bearerTokenDep = Package.Dependency.package(
        url: "https://github.com/mihaelamj/BearerTokenAuthMiddleware",
        from: "1.2.0"
    )

    // Apple-only dependencies (safe on Linux CI - only used by Apple targets)
    let fileWatchersDep = Package.Dependency.package(
        url: "https://github.com/krzysztofzablocki/KZFileWatchers.git",
        from: "1.0.0"
    )
    let injectDep = Package.Dependency.package(
        url: "https://github.com/krzysztofzablocki/Inject.git",
        from: "1.2.4"
    )
    let playbookDep = Package.Dependency.package(
        url: "https://github.com/playbook-ui/playbook-ios",
        from: "0.4.0"
    )

    return [
        openAPIGeneratorDep,
        openAPIRuntimeDep,
        openAPIVaporDep,
        vaporDep,
        fluentDep,
        fluentSQLiteDep,
        loggingMiddlewareDep,
        bearerTokenDep,
        fileWatchersDep,
        injectDep,
        playbookDep,
    ]
}()
```

Group dependencies by purpose (OpenAPI, Vapor, Middlewares, Apple-only), use descriptive variable names.

### Product Definition

```swift
// ---------- Products ----------
let allProducts: [Product] = {
    // Base products (all platforms)
    let apiSharedProduct = Product.singleTargetLibrary("ApiShared")
    let apiServerProduct = Product.singleTargetLibrary("ApiServer")
    let apiClientProduct = Product.singleTargetLibrary("ApiClient")
    let sharedModelsProduct = Product.singleTargetLibrary("SharedModels")
    let cachingMiddlewareProduct = Product.singleTargetLibrary("OpenAPICachingMiddleware")
    let serverAppProduct = Product.executable(name: "apiserverapp", targets: ["ApiServerApp"])

    let baseProducts: [Product] = [
        apiSharedProduct,
        apiServerProduct,
        apiClientProduct,
        sharedModelsProduct,
        cachingMiddlewareProduct,
        serverAppProduct,
    ]

    // Apple-only products (iOS + macOS)
    #if os(iOS) || os(macOS)
    let appColorsProduct = Product.singleTargetLibrary("AppColors")
    let appThemeProduct = Product.singleTargetLibrary("AppTheme")
    let sharedViewsProduct = Product.singleTargetLibrary("SharedViews")
    let authFeatureProduct = Product.singleTargetLibrary("AuthFeature")
    let appFeatureProduct = Product.singleTargetLibrary("AppFeature")
    let componentsProduct = Product.singleTargetLibrary("Components")
    let appComponentsProduct = Product.singleTargetLibrary("AppComponents")

    let appleOnlyProducts: [Product] = [
        appColorsProduct,
        appThemeProduct,
        sharedViewsProduct,
        authFeatureProduct,
        appFeatureProduct,
        componentsProduct,
        appComponentsProduct,
    ]
    #else
    let appleOnlyProducts: [Product] = []
    #endif

    // Always exposed (for Xcode scheme visibility)
    let playbookProduct = Product.singleTargetLibrary("PlaybookFeature")

    return baseProducts + appleOnlyProducts + [playbookProduct]
}()

// Helper extension
extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
```

Use local variables for each product, group by platform, use helper extensions for common patterns.

### Target Organization

Declare targets as individual variables inside a closure, group by layer, then return their concatenation.

```swift
let targets: [Target] = {
    // ---------- Shared Models ----------
    let sharedModelsTarget = Target.target(
        name: "SharedModels",
        dependencies: []
    )
    let sharedModelsTestsTarget = Target.testTarget(
        name: "SharedModelsTests",
        dependencies: ["SharedModels"]
    )
    let modelTargets = [
        sharedModelsTarget,
        sharedModelsTestsTarget,
    ]

    // ---------- API Layer ----------
    let apiSharedTarget = Target.target(
        name: "ApiShared",
        dependencies: [
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        ],
        plugins: [
            .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
        ]
    )
    let apiSharedTestsTarget = Target.testTarget(
        name: "ApiSharedTests",
        dependencies: ["ApiShared"]
    )
    let apiClientTarget = Target.target(
        name: "ApiClient",
        dependencies: [
            "ApiShared",
            "SharedModels",
        ]
    )
    let apiClientTestsTarget = Target.testTarget(
        name: "ApiClientTests",
        dependencies: ["ApiClient"]
    )
    let apiTargets = [
        apiSharedTarget,
        apiSharedTestsTarget,
        apiClientTarget,
        apiClientTestsTarget,
    ]

    // ---------- UI Components ----------
    let appThemeTarget = Target.target(
        name: "AppTheme",
        dependencies: []
    )
    let sharedViewsTarget = Target.target(
        name: "SharedViews",
        dependencies: [
            "AppTheme",
            "AppFont",
        ]
    )
    let uiTargets = [
        appThemeTarget,
        sharedViewsTarget,
    ]

    // Return all targets grouped by layer
    return modelTargets + apiTargets + uiTargets
}()
```

**Why this pattern:**
- ✅ Clear visual separation with comment headers (e.g., `// ---------- Shared Models ----------`)
- ✅ Each target has a descriptive variable name (`sharedModelsTarget`, not inline Target.target(...))
- ✅ Easy to reference targets within Package.swift (can reuse variable names)
- ✅ Groups targets by layer/domain for better organization
- ✅ Trailing commas in arrays for cleaner diffs
- ✅ Makes Package.swift more maintainable as project grows

Don't define targets inline in the array; use intermediate variables.

## See also

- [`core/folder-grouping.md`](../core/folder-grouping.md): when many single-file targets share a semantic kind (e.g. 27 importers, 5 renderers), they can colocate under a single parent folder using `path:` + disjoint `sources:` declarations. A `flatImporter(_:in:dependencies:)` helper is the worked example: 26 single-file importer targets share `Sources/Import/Importers/<cluster>/` paths while remaining independent SPM targets. The closure-with-local-variables pattern above still applies; the helper just returns a `Target.target(...)` with the path/sources baked in.

