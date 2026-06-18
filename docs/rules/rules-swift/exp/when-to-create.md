# When to Create a New Package

Always-loaded core. Use the decision tree first. The DO/DON'T list and the checklist below cover the corner cases.

## PACKAGE CREATION DECISION TREE

```
Need to add new code?
├─ Is it a reusable domain model?
│   └─ YES → Add to SharedModels
│
├─ Is it UI-related?
│   ├─ Colors/semantic colors? → Add to AppColors
│   ├─ Fonts/typography? → Add to AppFont
│   ├─ Combined theme? → Add to AppTheme (uses AppColors + AppFont)
│   ├─ Component system infrastructure? → Add to Components (core system)
│   ├─ Hot reload support? → Add to SharedComponents
│   ├─ Reusable app component? → Add to AppComponents
│   └─ View helper/modifier? → Add to SharedViews
│
├─ Is it a complete user-facing feature?
│   └─ YES → Create new *Feature package
│       Example: ProfileFeature, SettingsFeature, PaymentFeature
│
├─ Is it API/networking related?
│   ├─ Client-side? → Add to ApiClient (or create new client package)
│   ├─ Server-side? → Add to ApiServer
│   ├─ Shared DTOs? → Add to ApiShared (OpenAPI generated)
│   └─ Middleware? → Create new *Middleware package
│
├─ Is it shared infrastructure?
│   └─ YES → Create new Shared* package
│       Example: SharedUtilities, SharedNetworking
│
└─ Still unsure?
    └─ Ask: "Could this be reused in isolation?"
        ├─ YES → Create new package
        └─ NO → Add to most specific existing package
```

## WHEN TO CREATE A NEW PACKAGE

### ✅ DO Create New Package When:

1. **New Feature Module**
   - Complete user-facing feature (login, profile, payments)
   - Example: `ProfileFeature`, `PaymentFlowFeature`

2. **Reusable Infrastructure**
   - Can be tested in isolation
   - Might be used by multiple features
   - Example: `CachingMiddleware`, `LoggingUtility`

3. **Third-Party Integration**
   - Wraps external library
   - Isolates external dependencies
   - Example: `ApplePayIntegration`, `BiometricAuth`

4. **Platform Separation**
   - Platform-specific code (iOS vs macOS)
   - Example: `IOSBiometrics`, `MacOSNotifications`

5. **Build Optimization**
   - Large, stable code that rarely changes
   - Expensive compilation (generated code)
   - Example: `ApiShared` (OpenAPI generated)

### ❌ DON'T Create New Package When:

1. **Single Use Case**
   - Only used by one feature
   - Tightly coupled to specific screen
   - → Add to that feature's package

2. **Trivial Helper**
   - 1-2 small functions
   - No external dependencies
   - → Add to existing utility package

3. **Temporary Code**
   - Proof of concept
   - Spike/experiment
   - → Keep in feature until proven stable

## DECISION CHECKLIST

### Before Creating a New Package

- [ ] Package has single, clear responsibility
- [ ] Package name follows conventions (*Feature, Shared*, Api*, *Components)
- [ ] Dependencies are minimal and explicit
- [ ] No circular dependencies introduced
- [ ] Can be built and tested in isolation
- [ ] Fits into architectural layer (Foundation/Infrastructure/Feature/App)
- [ ] Test target created alongside source target
- [ ] Product registered in Package.swift products array
- [ ] Dependencies only flow upward (no higher-layer dependencies)

### Before Adding to Existing Package

- [ ] New code shares responsibility with existing code
- [ ] No better-suited package exists
- [ ] Not creating a "God package" with mixed concerns
- [ ] Won't introduce unwanted dependencies to package consumers

### Before Modifying Package.swift

- [ ] Used closure-with-local-variables pattern for `deps`
- [ ] Used closure-with-local-variables pattern for `allProducts`
- [ ] Used closure-with-local-variables pattern for `targets`
- [ ] NEVER used inline array definitions
- [ ] Grouped dependencies by purpose (OpenAPI, Vapor, Apple-only, etc.)
- [ ] Grouped products by platform (base vs. appleOnly)
- [ ] Grouped targets by layer (Foundation, Infrastructure, Features)
- [ ] Used comment headers (e.g., `// ---------- Shared Models ----------`)
- [ ] In `Package.swift`: separated platform-specific code with `#if os(iOS) || os(macOS)`
- [ ] In `Package.swift` only: did NOT use `#if canImport(UIKit)` (manifest evaluates it lazily and breaks Linux CI; `#if os()` is manifest-parse-time and safe). In regular Swift source files, `#if canImport(UIKit)` / `#if canImport(AppKit)` is the correct idiom for platform-conditional code.
- [ ] Each target/product/dependency has descriptive variable name
- [ ] Used trailing commas in all arrays
- [ ] Applied `.when(platforms:)` for platform-specific dependencies within targets

### Before Adding Font/Resource Package

- [ ] Used `.process()` for resources, NEVER `.copy()`
- [ ] Created `FontRegistration.swift` with CoreText registration
- [ ] Used `Bundle.module` for resource access, NEVER `Bundle.main`
- [ ] Used `#if canImport(UIKit)` / `#if canImport(AppKit)` for platform imports
- [ ] Filtered font files by extension (.otf, .ttf)
- [ ] Used `CTFontManagerRegisterFontsForURL` with error handling
- [ ] Added console logging for registration success/failure
- [ ] Called `FontRegistration.registerFonts()` in app init BEFORE UI renders
- [ ] NEVER used Info.plist font registration (`UIAppFonts`, `ATSApplicationFontsPath`)
- [ ] Package has zero dependencies (fonts are Foundation layer)
- [ ] Resources organized in dedicated subdirectory (e.g., `Fonts/`)

