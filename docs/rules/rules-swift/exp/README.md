# exp/: ExtremePackaging Architecture (Swift)

This folder is the canonical Swift package-architecture rule, formerly the single file `exp.md` (~1700 lines). Split into focused sub-files so the always-loaded set is small and the reference content is loaded on demand.

Follow the "ExtremePackaging" architecture pattern: a monorepo with maximum granular modularization into distinct SPM packages. Each package represents a single cohesive responsibility with explicit dependencies. This enables isolated compilation, parallel builds, clear dependency graphs, and superior testability.

## Always-load core

These two files are loaded in every Swift session. Together they cover the rule statements and the new-package decision flow:

| File | Purpose |
|---|---|
| `critical-rules.md` | Rule 1 to 5: single responsibility, explicit deps, granularity, naming, layer architecture |
| `when-to-create.md` | Decision tree, DO/DON'T new-package list, decision checklist |

## Reference (load on demand)

| File | When to load |
|---|---|
| `implementation-patterns.md` | Adding a foundation/feature/middleware/API/component/font package; building an aggregator |
| `dependency-management.md` | Adding a cross-package dependency; platform-conditional code (`#if os()`); circular-dep concerns |
| `package-swift.md` | Editing `Package.swift` (`deps`, `allProducts`, `targets` arrays) |
| `common-mistakes.md` | Code review or self-review of `Package.swift` changes |
| `app-target.md` | Adding or modifying an app target (SwiftUI, UIKit, AppKit entry points) |
| `testing.md` | Wiring or restructuring a package's test target (architecture angle; full testing rules in top-level `testing.md`) |
| `migration.md` | Extracting code into a new package or splitting a large one |
| `build-performance.md` | Rationale; read once for context, not normally needed during work |
| `verification.md` | Final checklist before considering an ExtremePackaging change done |

## Concrete example

The canonical Swift monorepo this rule was derived from has the following 20-package layout. Treat as illustrative, not normative; your project's package list will differ.

```
Packages/Sources/
├── Foundation Layer (0 dependencies)
│   ├── SharedModels          # Domain models, no dependencies
│   ├── AppColors             # Color system (HSV, semantic colors)
│   └── AppFont               # Typography, font loading
│
├── Design System Layer
│   └── AppTheme              # Combines AppColors + AppFont
│
├── Infrastructure Layer
│   ├── ApiShared             # OpenAPI spec + generated DTOs
│   ├── ApiClient             # Client-side networking (depends: ApiShared, SharedModels)
│   ├── ApiServer             # Vapor backend (depends: ApiShared, SharedModels)
│   ├── ApiServerApp          # Server executable (depends: ApiServer)
│   └── OpenAPICachingMiddleware  # Caching layer (depends: OpenAPIRuntime)
│
├── Component Layer
│   ├── Components            # CORE component system (AnyComponent, ComponentRegistry, ComponentFactory, etc.)
│   ├── SharedComponents      # Hot reload infrastructure (depends: Inject, KZFileWatchers)
│   ├── AppComponents         # Production app components (depends: Components, AppColors, AppFont)
│   └── AllComponents         # Umbrella package (depends: Components, AppComponents)
│
├── Feature Layer
│   ├── SharedViews           # Reusable views (depends: AppColors, AppFont)
│   ├── AuthFeature           # Authentication (depends: SharedModels, SharedViews)
│   ├── AppFeature            # Main app (depends: SharedModels, SharedViews, AuthFeature)
│   ├── BetaSettingsFeature   # Beta settings (depends: SharedModels, ApiClient)
│   ├── DemoAppFeature        # Demo mode (depends: SharedModels, ApiClient)
│   └── PlaybookFeature       # Component gallery (depends: Components, AppComponents)
│
└── Apps/ (not in Packages/Sources)
    ├── iosApp                # iOS target
    ├── macApp                # macOS target
    ├── ComponentsPreview     # Component preview app
    └── Demo                  # Demo app
```
