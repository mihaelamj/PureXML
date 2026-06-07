# Package Architecture

PureXML starts as one root Swift package with one library target:

- product: `PureXML`
- target: `PureXML`
- tests: `PureXMLTests`

## Rules

- Keep dependencies explicit and minimal.
- Keep external dependencies at zero unless the maintainer explicitly changes the
  project contract.
- Add a new target only when a responsibility needs independent compilation,
  testing, or platform boundaries.
- Keep dependencies unidirectional if new targets are added.

## Current Layers

```text
PureXML
├── Model      ordered YAML value tree
├── Parsing    parser implementation
└── Emitting   dumper implementation
```

The public namespace tree mirrors this layout.

## When to Split a Target

Do not split for aesthetics. Split when one of these becomes true:

- the parser and emitter need independent platform gates
- a reusable scanner/lexer becomes large enough to test independently
- a compatibility layer for Yams-style decoding needs isolation from the core
  model
- a CLI or research tool appears and should not ship as library code
