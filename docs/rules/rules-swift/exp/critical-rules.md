# Critical Rules

Always-loaded core. Five rules that gate every Swift package decision under ExtremePackaging.

Follow the "ExtremePackaging" architecture pattern: a monorepo with maximum granular modularization into distinct SPM packages. Each package represents a single cohesive responsibility with explicit dependencies. This enables isolated compilation, parallel builds, clear dependency graphs, and superior testability.

### Rule 1: Single Responsibility per Package

Create packages with one clear purpose:
- A single, well-defined responsibility per package
- Don't mix concerns (UI + networking, models + API client)
- Name communicates the purpose
- Independently buildable and testable

### Rule 2: Explicit Dependency Declaration

Declare dependencies explicitly in `Package.swift`:
- List all dependencies in the package manifest
- No implicit/transitive dependencies
- Minimise cross-package dependencies
- Prefer unidirectional dependency flow

### Rule 3: Package Granularity

Prefer smaller, focused packages over larger ones:
- Single-file packages are acceptable when the unit is genuinely standalone (typography, color foundation, a single protocol, a single transport).
- Separate by role, not by topical bundling: foundation primitives, infrastructure, protocols, middleware, services, per-feature or per-CLI-verb operation packages, front-door binaries.
- Each cohesive responsibility (a feature, a CLI verb, a middleware, a transport, a service) gets its own package.

### Rule 4: Naming Conventions

Follow a consistent naming scheme. Patterns that apply across project shapes:

- **Shared foundation:** `Shared*` for cross-target value-types, models, utilities, configuration (e.g. `SharedModels`, `SharedUtils`, `SharedConfiguration`).
- **Core infrastructure:** `Core*` or descriptive single-purpose names for the foundation domain (protocols, parsers, transports, indexers).
- **Per-feature or per-verb operation packages:** one package per user-facing flow (UI app) or one per CLI/MCP verb (CLI/MCP app). Name after the responsibility, not after a role suffix (`Distribution`, `Indexer`, `Ingest` in a CLI; the feature's own name in a UI app).
- **Service packages:** `*Service` or a `Services` aggregator for cross-layer read/write services consumed by multiple front-doors.
- **Aggregators:** umbrella packages only when the umbrella adds real value (preview hosts, all-features aggregators for app composition); don't add one by default.

Project-specific conventions (UI component packages, API client/server splits, design-system packages, hot-reload infrastructure) live in the project's own `AGENTS.md` or rule files, not in this always-loaded universal rule.

### Rule 5: Layer Architecture

Organize packages into clear architectural layers with unidirectional dependency flow (bottom → top). The number and naming of layers varies per project shape; the constants are:

- **Foundation** (bottom): shared value-types, models, primitive utilities, logging.
- **Infrastructure**: protocols, persistence, networking, file I/O, parsers, transports.
- **Domain**: services, indexers, business logic, per-feature or per-CLI-verb operation packages.
- **Presentation** (UI projects only): component packages, design-system packages, screens.
- **Front-door** (top): binary targets, apps, CLIs, MCP servers, preview hosts, test harnesses.

Every dependency edge points upward. No back-edges. For the active project's actual layer instantiation, read `Packages/Package.swift`.

