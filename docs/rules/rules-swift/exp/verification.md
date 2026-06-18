# Verification

Final checklist before considering an ExtremePackaging change done.

When applying these rules, always:
1. Check current package structure matches documented 20-package layout
   - Foundation: SharedModels, AppColors, AppFont
   - Design System: AppTheme
2. Verify new packages follow naming conventions
3. Ensure dependencies flow unidirectionally (Foundation → Infrastructure → Features → Apps)
4. Create test targets for all new packages
5. Update Package.swift using closure-with-local-variables pattern:
   - Define `deps`, `allProducts`, and `targets` using `let variable: [Type] = { ... }()` pattern
   - NEVER use inline array definitions
   - Use descriptive variable names for each dependency, product, and target
   - Group by purpose/layer with comment headers (`// ---------- Header ----------`)
   - Separate platform-specific code with `#if os(iOS) || os(macOS)`
6. Run `swift build` to verify package integrity
7. Verify Package.swift follows all formatting rules:
   - Trailing commas in arrays
   - Grouped dependencies (OpenAPI, Vapor, Apple-only)
   - Grouped products (base, appleOnly)
   - Grouped targets (modelTargets, apiTargets, uiTargets)
8. Check platform separation in `Package.swift` uses `#if os()`, not `#if canImport()`. (Inside Swift source files, `#if canImport(UIKit)` / `#if canImport(AppKit)` is the correct idiom; the manifest is the only place `canImport` is forbidden.)
9. Verify `.when(platforms:)` used for platform-specific dependencies within targets
10. For font/resource packages:
    - Confirm `.process()` used for resources (NOT `.copy()`)
    - Verify `Bundle.module` used (NOT `Bundle.main`)
    - Check CoreText registration implemented with error handling
    - Ensure registration called in app init before UI renders
    - Verify no Info.plist font registration used
