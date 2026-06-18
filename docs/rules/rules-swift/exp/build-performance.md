# Build Performance Benefits

Why ExtremePackaging pays off in build time. Rationale, not rule. Read once for context.

### Incremental Compilation

**With ExtremePackaging:**
- Change AppFont → Only AppFont rebuilds
- Change AppComponents → Only AppComponents + dependent targets rebuild
- Change SharedModels → More rebuilds (foundation layer), but still isolated

**Without ExtremePackaging:**
- Change any file → Entire monolith rebuilds

### Parallel Builds

```
Build Graph (simplified):
SharedModels ─┬─> ApiClient ─┬─> AuthFeature ──> iosApp
              │               │
              └─> AppTheme ───┴─> AppFeature ───┘

SPM builds in parallel:
[SharedModels, AppFont] → [ApiClient, AppTheme, SharedViews] → [AuthFeature, AppFeature] → [iosApp]
```

SPM automatically parallelizes independent package builds.

### CI/CD Optimization

```yaml
# A CI runner can cache per-package
stages:
  - build-foundation
  - build-infrastructure
  - build-features
  - build-apps

build-foundation:
  script:
    - swift build --product SharedModels
    - swift build --product AppTheme
  # Cache: Only rebuild if foundation changed
```

