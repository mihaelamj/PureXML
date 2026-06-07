# Changelog

All notable changes to PureXML are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial package scaffold: root Swift package, namespacing under `PureXML`, and
  the portability and verification gates carried over from PureYAML.
- XML node model (`PureXML.Model`): `Node`, `Element`, `Attribute`, and
  `QualifiedName`, preserving document order and node kinds.
- XML emitter (`PureXML.Emitting.Serializer`) with pretty-printed and compact
  output and correct text and attribute escaping.
- Structural validation (`PureXML.Validation.Validator`) for duplicate attribute
  names.
- Stable parser surface (`PureXML.Parsing.Parser`, `ParseError`, `Mark`).
  `PureXML.parse(_:)` raises `ParseError.notImplemented` until the scanner lands;
  the gap is pinned by a test.
