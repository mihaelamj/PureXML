# Migration Patterns

Extracting code into a new package; splitting a large package.

### Extracting Code to New Package

```bash
# 1. Create new package structure
mkdir -p Packages/Sources/NewPackage
mkdir -p Packages/Tests/NewPackageTests

# 2. Move files
git mv OldPackage/SomeFeature.swift NewPackage/

# 3. Update Package.swift
# Add new target and product

# 4. Update imports in dependent files
# Change: import OldPackage
# To: import NewPackage

# 5. Rebuild
cd Packages && swift build

# 6. Run tests
swift test --filter NewPackageTests
```

### Splitting Large Package

```swift
// Before: Large "Features" package
Features/
├── Auth/
├── Profile/
└── Settings/

// After: Separate feature packages
AuthFeature/
ProfileFeature/
SettingsFeature/
```

