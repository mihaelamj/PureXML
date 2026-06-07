# PureXML

[![macOS CI](https://img.shields.io/github/actions/workflow/status/mihaelamj/PureXML/ci.yml?branch=main&label=macOS)](https://github.com/mihaelamj/PureXML/actions/workflows/ci.yml)
[![Linux CI](https://img.shields.io/github/actions/workflow/status/mihaelamj/PureXML/ci.yml?branch=main&label=Linux)](https://github.com/mihaelamj/PureXML/actions/workflows/ci.yml)
[![WASI CI](https://img.shields.io/github/actions/workflow/status/mihaelamj/PureXML/ci.yml?branch=main&label=WASI)](https://github.com/mihaelamj/PureXML/actions/workflows/ci.yml)

PureXML is a dependency-free XML package written entirely in Swift.

The goal is a Linux-, Windows-, and WebAssembly-compatible XML reader/writer that
does not pull in `libxml2`, `expat`, or Foundation's `XMLParser`. The package is
intentionally strict about portability:

- no external SwiftPM dependencies
- no bundled C sources
- no Foundation requirement in the library target
- root Swift package layout
- macOS, Linux, Windows, and WASI build gates

It is a sibling project to [PureYAML](https://github.com/mihaelamj/PureYAML) and
follows the same structure, rules, and verification gates.

## Status

This is an early scaffold. The node model and the emitter are implemented and
usable today; the tokenizing parser is still being built.

- **Model** (`PureXML.Model`): `Node`, `Element`, `Attribute`, `QualifiedName`.
  Preserves document order and the distinction between text, CDATA, comments,
  and processing instructions.
- **Emitting** (`PureXML.Emitting`): `Serializer` turns a node tree into
  well-formed XML, with pretty-printed and compact options and correct text and
  attribute escaping.
- **Validation** (`PureXML.Validation`): structural checks such as duplicate
  attribute names. Schema validation (DTD/XSD/RELAX NG) is out of scope for the
  library target.
- **Parsing** (`PureXML.Parsing`): the public surface (`Parser`, `ParseError`,
  `Mark`) is stable. `PureXML.parse(_:)` currently raises
  `ParseError.notImplemented` so callers can wire against the final API before
  the scanner lands. The gap is pinned by a test rather than left silent.

## Usage

```swift
import PureXML

// Build a tree and emit it (works today).
let element = PureXML.Model.Element(
    "book",
    attributes: [.init("id", "bk101")],
    children: [.element(.init("title", children: [.text("XML Developer's Guide")]))],
)

let xml = PureXML.serialize(.element(element))
try PureXML.validate(.element(element))

// Parsing is not implemented yet:
// let node = try PureXML.parse(xml)
```

## Attribution

PureXML is informed by the behavior of established XML parsers (`libxml2`,
`expat`, Foundation's `XMLParser`) and by the W3C XML 1.0 specification, but it
does not copy their implementation into `Sources/`. See
[ATTRIBUTION.md](ATTRIBUTION.md).

## Development Contract

PureXML must stay dependency-free and portable. Before merging changes:

- Swift tools version: 6.1
- Package products: `PureXML`
- SwiftPM dependencies: none
- Hosted CI matrix: macOS, Linux, Windows, and WASM

```sh
bash scripts/check-all.sh
```

That command expands to:

```sh
bash scripts/check-style.sh
bash scripts/check-namespacing.sh
bash scripts/check-forbidden-patterns.sh
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml --strict
swift build
swift test
```

## License

MIT.
