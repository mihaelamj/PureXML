# Package and Repository Structure

PureXML is a root Swift package.

## Required Layout

```text
PureXML/
├── Package.swift
├── Sources/
│   ├── PureXML.swift
│   ├── Model/
│   ├── Parsing/
│   └── Emitting/
├── Tests/
│   └── PureXMLTests/
├── docs/
└── scripts/
```

## Rules

- Keep `Package.swift` at repository root.
- Do not create a `Packages/` folder.
- Keep production code directly under `Sources`.
- Keep tests in `Tests/PureXMLTests`.
- Keep `Package.swift` dependency-free.
- Add new targets only when a responsibility genuinely needs isolation.

## Namespace Mapping

The namespace tree mirrors the source tree:

- `Sources/Model/Value.swift` -> `PureXML.Model.Value`
- `Sources/Parsing/Parser.swift` -> `PureXML.Parsing.Parser`
- `Sources/Emitting/Dumper.swift` -> `PureXML.Emitting.Dumper`

The root namespace file, `Sources/PureXML.swift`, is a map of namespaces only.
