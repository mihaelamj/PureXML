# Changelog

All notable changes to PureXML are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Configurable, bounded-by-default parser limits (`PureXML.Parsing.Limits`):
  maximum nesting depth (default 256), name length, and content length, enforced
  during scanning. Protects against pathological input and keeps the recursive
  node model safe to build and tear down. Threaded through `parse`/`events`.
- Initial package scaffold: root Swift package, namespacing under `PureXML`, and
  the portability and verification gates carried over from PureYAML.
- XML node model (`PureXML.Model`): `Node`, `Element`, `Attribute`, and
  `QualifiedName`, preserving document order and node kinds.
- XML emitter (`PureXML.Emitting.Serializer`) with pretty-printed and compact
  output and correct text and attribute escaping.
- Structural validation (`PureXML.Validation.Validator`) for duplicate attribute
  names.
- Streaming, iterative XML parser. `PureXML.Parsing.EventReader` is a pull-based
  event core that consumes input through a character-source closure and emits one
  `Event` at a time, holding only bounded state (an open-element stack and a small
  lookahead buffer). It never requires the whole document in memory and can drive
  chunked input. `PureXML.Parsing.Parser` builds a `Model.Node` tree iteratively
  over the event core (no recursion). Handles elements, attributes, text, the five
  predefined entities and numeric character references, comments, CDATA, and
  processing instructions. Safe by default: `<!DOCTYPE>` is rejected (no DTD/XXE).
- Top-level API: `PureXML.parse(_:)`, `PureXML.parse(pulling:)`, and
  `PureXML.events(_:)` / `PureXML.events(pulling:)` for streaming.

### Changed

- The emitter is now iterative (explicit work stack, not recursion), mirroring
  libxml2's approach, so deep trees do not overflow the call stack.
- The emitter escapes tab/newline/CR (and `>`) in attribute values so attributes
  round-trip through spec-compliant parsers; mixed content is no longer
  reformatted (formatting is suppressed for elements with text/CDATA children).
