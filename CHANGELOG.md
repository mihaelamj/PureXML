# Changelog

All notable changes to PureXML are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Push / feed streaming API (#1), the last epic. A resumable scanner reports a
  token only once its terminator is fully buffered and otherwise signals
  need-more (the Expat `XML_TOK_PARTIAL` model), so `PureXML.Parsing.PushParser`
  parses input fed in arbitrary chunks with `feed(_:)`/`finish()`, driving a
  `SAXHandler`, while retaining only the current incomplete token plus the
  open-element stack. `PureXML.events(feeding:)` exposes an `AsyncThrowingStream`
  of events over any async sequence of text chunks. Splitting a document at any
  byte boundary, down to one character per feed, yields identical events.
- HTML parser and serializer (#20, the libxml2 `HTMLparser.h`/`HTMLtree.h`
  model). `PureXML.HTML.parse` reads tag-soup HTML leniently (case-insensitive
  tags; quoted, unquoted, and boolean attributes; comments; doctype; character
  references) and builds a node tree handling void elements (no end tag),
  optional end tags (implicit close of `li`, `p`, table rows and cells, and the
  like), raw-text elements (`script`, `style`), and unmatched end tags.
  `PureXML.HTML.serialize` writes it back with void elements unclosed and
  raw-text content unescaped.
- XSLT 1.0 transformation engine, completing #3. `PureXML.XSLT.transform`
  applies a stylesheet to a source document by the XSLT processing model: it
  matches each node to the highest-priority template (or the built-in rules) and
  instantiates the template's sequence constructor. Implements `apply-templates`
  (with template dispatch and `sort`), `value-of`, `for-each`, `if`, `choose`,
  `element`, `attribute`, `copy`, `copy-of`, `call-template`, `variable`, literal
  result elements, and attribute value templates, all over the existing XPath
  engine. The identity transform round-trips a document including its attributes.
- XSLT 1.0 stylesheet model and parser (toward #3). `PureXML.XSLT` gains a
  stylesheet model (template rules with match patterns and computed default
  priorities, the instruction sequence constructor, attribute value templates)
  and a parser that compiles an `xsl:stylesheet` document into it. Recognizes the
  XSLT vocabulary by namespace or `xsl` prefix; other elements are literal result
  elements. Supports `template`, `apply-templates`, `value-of`, `for-each`, `if`,
  `choose`, `element`, `attribute`, `copy`, `copy-of`, `call-template`,
  `variable`, `text`, and `sort`.
- Schema conformance fixtures, completing XSD and RELAX NG validation (#2). A
  cross-cutting suite validates realistic schemas (a patterned, bounded,
  ID-keyed XSD purchase order and a RELAX NG contact card using interleave,
  attribute value choices, and optional/repeatable elements) against conforming
  and non-conforming instances, plus datatype boundary fixtures.
- RELAX NG validation by derivatives (toward #2). `PureXML.Schema.RelaxNG`
  parses a RELAX NG schema in the XML syntax into a pattern grammar (`element`,
  `attribute`, `text`, `empty`, `notAllowed`, `group`, `choice`, `interleave`,
  `optional`, `zeroOrMore`, `oneOrMore`, `mixed`, `list`, `ref`/`define`, `data`,
  `value`, and the name classes), and `validate(_:)` checks an instance document
  by James Clark's derivative algorithm: the pattern is derived through each
  start-tag, attribute, text, and end-tag event, and the document is valid when
  the residual pattern is nullable. Handles interleave, recursive grammars, and
  reuses the XSD datatype library for `data`/`value`.
- XSD schema-document parser, completing the XSD validation pipeline (toward #2).
  `PureXML.Schema.Document(xsd)` compiles a schema document into its global
  element declarations and named-type table, and `validate(_:)` checks an
  instance document end to end. The parser matches the schema vocabulary by local
  name and supports global and local element declarations, named and inline
  simple and complex types, `sequence`/`choice`/`all` model groups with
  occurrence, attribute uses, simple content (restriction/extension), the full
  facet set, and recursive types (via named type references resolved during
  validation).
- XSD complex types and particles (toward #2 schema validation).
  `PureXML.Schema.ComplexValidator` validates an element against a
  `ComplexType`: its attribute uses (required and typed, with unknown-attribute
  rejection), and its content model. Content is `empty`, `simpleContent` (text
  validated against a simple type), `elementOnly`, or `mixed`. Particles compile
  to a Thompson NFA over element names honoring `minOccurs`/`maxOccurs`, with
  `sequence`/`choice` compositors; `all` groups are validated order-independently
  by counting. Child elements are validated recursively against their declared
  types (the XSD Element-Declarations-Consistent rule makes the name-to-type map
  well defined).
- XSD simple-type datatype library (toward #2 schema validation). The new
  `PureXML.Schema` namespace validates a lexical value against the XSD Part 2
  built-in datatypes (`string`, `boolean`, `decimal`, the bounded integer family,
  `float`/`double`, `duration`, the eight date/time types, `hexBinary`,
  `base64Binary`, `anyURI`, `QName`, and the `Name`/`NCName`/`NMTOKEN`/`language`
  family) and the constraining facets (`length`/`minLength`/`maxLength`,
  `pattern` via the regex engine, `enumeration`, `whiteSpace`,
  `min`/`maxInclusive`/`Exclusive`, `totalDigits`, `fractionDigits`). Decimals are
  compared exactly with no floating-point loss, date/time fields are
  range-validated (leap years, `24:00:00`, timezone bounds), and the integer
  types enforce their intrinsic bounds.
- Regular-expression engine (#30, the XML Schema regex flavor, gating XSD). The
  new `PureXML.Regex` namespace compiles a pattern (literals, `.`, character
  classes with ranges and negation, the escapes `\d \D \w \W \s \S \i \I \c \C`,
  single-character escapes, grouping, alternation, and the quantifiers `?`, `*`,
  `+`, `{n}`, `{n,}`, `{n,m}`) to a Thompson NFA and matches the whole string, as
  `xs:pattern` facets require. Matching is linear in the input with no
  backtracking blow-up. `\p{...}` Unicode category escapes are not yet supported.
- Canonical XML (#26, the libxml2 `c14n.h` model). The new `PureXML.Canonical`
  namespace renders the C14N form of a node: namespace declarations sorted by
  prefix (default first) and attributes by namespace URI then local name, empty
  elements expanded to start/end pairs, CDATA folded into escaped text, and the
  C14N text/attribute escaping rules. Inclusive mode renders every in-scope
  namespace; exclusive mode renders only the namespaces an element and its
  attributes visibly use (with an `InclusiveNamespaces` prefix list). Comments
  are omitted unless requested. For whole-tree canonicalization C14N 1.0 and 1.1
  coincide, so the single inclusive mode covers both.
- XInclude, URI resolution, and `xml:base` (#24, the libxml2 `xinclude.h`/`uri.h`
  model). The new `PureXML.XInclude` namespace adds RFC 3986 reference
  resolution (`URIReference.resolve(_:against:)`, with dot-segment removal) and
  `process(_:base:loadingURI:)`, which replaces `xi:include` elements with their
  targets. `href`s resolve against the supplied base and the in-scope `xml:base`,
  `parse="xml"` includes the document element (or an `xpointer()` fragment via
  `PureXML.XPointer`), `parse="text"` includes raw text, and a failed load uses
  `xi:fallback` or errors. Includes nest. PureXML does no I/O itself: fetching is
  only through the injected `loadingURI` closure, so the default fetches nothing.
- XML Catalog resolution (#27, the libxml2 `catalog.h` model). The new
  `PureXML.Catalog` namespace parses an OASIS XML catalog (matching `public`,
  `system`, `uri`, `rewriteSystem`, `rewriteURI`, and `group`/`catalog` by local
  name) into a `Resolver` that maps public/system identifiers and URI names to
  replacement URIs, with longest-prefix rewriting and system-over-public
  precedence. `Resolver.entityResolver(loadingURI:)` builds a
  `Parsing.EntityResolver` that resolves an external identifier through the
  catalog and then loads the URI via an injected closure, so a catalog plus a
  loader wires external entities and DTDs in while the default (no loader) keeps
  XXE closed.
- Schematron validation (#25, the libxml2 `schematron.h` model).
  `PureXML.Validation.Schematron(schema:)` compiles a Schematron schema
  (namespace-agnostic over the ISO and legacy namespaces) and `validate(_:)`
  checks a document: each `<rule>`'s `context` XPath selects the nodes it fires
  on, and each `<assert>`/`<report>` `test` is evaluated relative to that node, a
  failed assert becoming an error issue and a matched report a warning. Within a
  pattern a node fires the first matching rule. Built on the XPath context-node
  evaluation, with a new `XPath.Query.nodes(over:)` that returns matched tree
  nodes for repeated querying of one tree.
- XPointer (#23, the libxml2 `xpointer.h` schemes). The new `PureXML.XPointer`
  namespace resolves the shorthand bare-name form (`name` = `id('name')`), the
  `element()` scheme (child-element positions from an id or the document root,
  e.g. `element(intro/2)`, `element(/1/2)`), and the `xpointer()` scheme (a full
  XPath expression). A pointer may chain scheme parts; they are tried in order
  and the first non-empty selection wins (the fallback rule). Built on
  `PureXML.XPath`.
- Streaming pattern matching (#22, the libxml2 `pattern.h` model). The new
  `PureXML.Pattern` namespace compiles the streamable XPath subset (element
  names, `*`, `prefix:*`, `/`, `//`, a leading absolute `/`, and a trailing
  attribute step) into a `Matcher`, rejecting predicates and `.`/`..` as outside
  the subset. `PureXML.Pattern.matches(_:in:)` streams a document through the
  pull parser and returns the paths of matching nodes (`/a/b/c`, `/a/@id`) in
  document order, deciding each match from the open-element stack alone, so no
  tree is built. `Matcher.matchesElement(path:)` reuses a compiled pattern.
- The XPath evaluation context, completing full XPath 1.0 (#21).
  `Query.value(at:position:size:variables:)` evaluates an expression against an
  explicit context node already in a tree, with its proximity position, size,
  and variable bindings, so `position()`, `last()`, and the upward axes resolve
  from that node. This is the per-node entry point downstream engines (XSLT,
  Schematron) drive.
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
