# Changelog

All notable changes to PureXML are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The full XPath 1.0 function library (toward #21 full XPath 1.0). Beyond the
  core functions, the string family (`concat`, `starts-with`, `contains`,
  `substring-before`, `substring-after`, `substring`, `string-length`,
  `normalize-space`, `translate`), the number family (`sum`, `floor`, `ceiling`,
  `round`), and the node family (`local-name`, `name`, `namespace-uri`, `id`,
  `lang`). All pure Swift with no Foundation. Without a DTD, `id()` matches by an
  attribute named `id` or `xml:id`.
- The XPath expression engine and four-type model (toward #21 full XPath 1.0).
  `PureXML.XPath.Query` now compiles and evaluates full expressions, not just
  location paths: the operator grammar (`or`, `and`, `=`, `!=`, `<`, `<=`, `>`,
  `>=`, `+`, `-`, `*`, `div`, `mod`, unary `-`, `|`) with correct precedence,
  number and string literals, function calls, variable references, and filter
  expressions, all over `PureXML.XPath.Value` (node-set, boolean, number,
  string) with the spec's coercion rules and canonical number formatting.
  Predicates are now arbitrary expressions (a numeric predicate is a position
  test). Query gains `value(over:variables:)`, `number`, `string`, and `boolean`
  accessors, and a binding map for `$variables`. The core functions `last`,
  `position`, `count`, `not`, `true`, `false`, `boolean`, `number`, and `string`
  ship with it.
- All thirteen XPath axes (toward #21 full XPath 1.0). `PureXML.XPath.Query` now
  navigates `child`, `descendant`, `parent`, `ancestor`, `following-sibling`,
  `preceding-sibling`, `following`, `preceding`, `attribute`, `namespace`,
  `self`, `descendant-or-self`, and `ancestor-or-self`, with the `.`/`..`/`@`/`//`
  abbreviations and the `processing-instruction()` node test. Evaluation runs
  over the parent-aware tree, so upward and sibling navigation are first-class;
  results come back de-duplicated and in document order regardless of axis
  direction. The attribute axis excludes `xmlns` declarations and the namespace
  axis surfaces in-scope namespace nodes.
- Pull-cursor reader (the libxml2 `xmlTextReader` model).
  `PureXML.Parsing.TextReader` (via `PureXML.reader(_:)`) walks a document one
  node at a time with `read()`, exposing `nodeKind`, `name`, `value`, `depth`,
  `attributes`/`attributeCount`/`attribute(_:)`, and `isEmptyElement` at each
  step. It layers on the streaming core, so it never holds the whole document.
  A childless element is reported once as an empty element (no separate end
  node), normalizing `<a/>` and `<a></a>`. `documentType` surfaces the DTD read
  so far as the validation hook.
- Mutable, parent-aware document tree (the libxml2 `tree.h` model).
  `PureXML.Model.TreeNode` is a reference type that knows its parent and
  siblings, so a document can be navigated upward and sideways (`parent`,
  `nextSibling`, `previousSibling`, `ancestors`, `root`, `elementChildren`,
  `stringValue`) and edited in place (`append`, `insert(before:)`,
  `insert(after:)`, `removeFromParent`, `replace(with:)`, `copy`). Children are
  held strongly and the parent weakly; attaching a node detaches it from any
  previous parent, and a node can never become its own ancestor. `parseTree(_:)`
  builds one from XML and `TreeNode.node` converts back to the value tree for
  serialization.
- External and parameter entities (the libxml2 `entities.h` model), secure by
  default. Internal parameter entities (`<!ENTITY % name "value">`) are stored
  and expanded within the DTD, including bare `%name;` references that inject
  markup declarations, bounded by depth and the expansion budget. External
  general entities and the external DTD subset are recorded but never fetched by
  PureXML itself: they are loaded only through an injected
  `PureXML.Parsing.EntityResolver` (a struct of closures). The default resolver
  refuses every external reference, so XXE stays closed; an external entity then
  fails as undefined and the external subset is left unread. Internal
  declarations win over the external subset.
- Serialization option parity for the XML declaration (the libxml2 save-option
  model). `PureXML.Emitting.Options` gains `includeXMLDeclaration`, `xmlVersion`,
  `encodingName`, and `standalone`; when requested, both the tree serializer and
  the incremental writer prepend an `<?xml ...?>` declaration from a single shared
  computation. `Writer.writeStartDocument()` emits it. Defaults stay off so
  fragment output is unchanged.
- Spec-exact XML character classification (`PureXML.Parsing.XMLCharacter`, the
  libxml2 `chvalid.h` parity): the XML 1.0 (Fifth Edition) `Char`,
  `NameStartChar`, and `NameChar` productions as public predicates over Unicode
  scalars, plus `isValidName(_:)`. The scanner's name recognition now uses these
  exact ranges (replacing a loose `isLetter` check) from a single source of truth,
  and handles both precomposed and combining-mark names.
- Full encoding support. Byte input now decodes UTF-32 (both byte orders, BOM or
  sniffed) and the single-byte encodings ISO-8859-1 and Windows-1252 selected by
  the XML declaration's `encoding` name, in addition to UTF-8 and UTF-16. The
  streaming byte path also decodes UTF-32. Standard library only, no Foundation.
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
