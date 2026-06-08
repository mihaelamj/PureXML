# Changelog

All notable changes to PureXML are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Incremental XML writer (`PureXML.Emitting.Writer`, the libxml2 `xmlTextWriter`
  model): emit a document with start/end and write calls without building a tree.
  Escaping matches the tree serializer (extracted into a shared `Escaping` helper),
  so compact output is byte-identical to serializing the equivalent tree.
- SAX2 push-callback parsing (the libxml2 SAX2 model). `PureXML.Parsing.SAXHandler`
  is a struct of optional callbacks (start/end document, start/end element,
  characters, CDATA, comment, processing instruction); `PureXML.parse(_:sax:)`
  drives them from the streaming core. Element names are namespace-resolved, so
  the URI is available on each callback.
- DTD ID/IDREF validation. Attributes typed `ID` must be unique across the
  document; `IDREF` and `IDREFS` values must each resolve to a declared `ID`
  (forward references included, via a second pass). Completes the structural DTD
  validation layer alongside content models and attribute rules.
- DTD attribute validation (`<!ATTLIST>`). The parser surfaces attribute
  declarations alongside element models, and `DTDSchema` now checks `#REQUIRED`
  attributes are present, `#FIXED` attributes match when present, and enumerated
  attributes take a declared value. Tokenized types (ID/IDREF/NMTOKEN) are parsed
  but their value rules (uniqueness, references) are not yet enforced.
- DTD content-model validation. The parser now surfaces the `<!DOCTYPE>` internal
  subset's `<!ELEMENT>` declarations (`PureXML.Parsing.DocumentType`, via
  `Parser.parseWithDocumentType`), and `PureXML.Validation.DTDSchema` validates a
  tree against them: `EMPTY`, `ANY`, `(#PCDATA)`, mixed content, and element
  content models (sequence/choice with `?`/`*`/`+`, matched as a regular language
  over child element names). `PureXML.validateAgainstInternalDTD(_:)` parses and
  validates in one call. `<!ATTLIST>` validation is not yet covered.
- XPath query support (a practical subset). `PureXML.XPath.Query` compiles a
  location path and evaluates it over a node; `PureXML.xpath(_:over:)` is the
  one-shot convenience. Supports the forward axes (child, descendant `//`, self
  `.`, attribute `@`), the node tests (name, `*`, `text()`, `node()`,
  `comment()`), and the predicates `[n]`, `[@a]`, `[@a='v']`, `[child]`,
  `[child='v']`. Returns a `Selection` node-set with `element` and `stringValue`
  accessors. Upward/sibling axes and the full expression language are out of
  scope (the model has no parent pointers).
- Optional DTD with internal general entities, off by default. With
  `Limits(allowDoctype: true)` the parser reads a `<!DOCTYPE>` internal subset,
  honors internal `<!ENTITY name "value">` declarations, and expands them in text
  and attribute values. Defenses are mandatory: expansion is bounded by
  `Limits.maxEntityExpansion` (billion-laughs amplification raises
  `ParseError.amplificationLimitExceeded`), recursive entities raise
  `ParseError.recursiveEntity`, undeclared entities raise
  `ParseError.undefinedEntity`, and external entities are never loaded (XXE stays
  closed). The default still rejects `<!DOCTYPE>` outright.
- Streaming byte decode. `PureXML.parse(pullingBytes:)` and
  `events(pullingBytes:)` accept an incremental byte source (`() -> UInt8?`) and
  decode UTF-8 or UTF-16 on the fly, so the bytes are never fully buffered.
  Encoding is detected from the leading bytes; invalid sequences become the
  Unicode replacement character rather than failing the stream.
- Namespace resolution. Qualified names now carry an optional resolved
  `namespaceURI`, populated by the parser from in-scope `xmlns` declarations at
  the start-element boundary (the libxml2 SAX2 model). A default namespace applies
  to unprefixed element names but not attributes, the `xml` prefix is built in,
  `xmlns` declarations are preserved as attributes for round-trip, and an unbound
  prefix raises `ParseError.undefinedNamespacePrefix`. Namespace-free documents
  are unchanged (URIs stay nil).
- Byte input with encoding detection. `PureXML.parse(bytes:)` and
  `PureXML.events(bytes:)` accept raw `[UInt8]` and detect the encoding (UTF-8 or
  UTF-16, with or without a byte-order mark) following the XML sniff order, then
  decode with the Swift standard library (no Foundation). `PureXML.Parsing.
  InputEncoding.detect(_:)` exposes the detector. Malformed input (such as an
  odd-length UTF-16 stream) raises `ParseError.malformedEncoding`.
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
