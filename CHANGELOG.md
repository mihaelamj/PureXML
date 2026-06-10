# Changelog

All notable changes to PureXML are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The HTML document builder's body is now constructed as a live mutable `TreeNode` tree with a single open-elements stack (the HTML5 model), attaching nodes to their parent as they open rather than accumulating children on close (#83, internal). Behavior is unchanged; this is the foundation the adoption agency algorithm needs to reparent already-built subtrees.
- DTD attribute validation is now decomposed into five named, independently composable `Validation` rules (#101): `DTD.requiredAttributes`, `fixedAttributeValues`, `enumeratedAttributeValues`, `tokenizedAttributeTypes`, and `notationAttributes`, replacing the single `attributeDeclarations` rule. Each is removable by identity and isolation-tested one constraint at a time, honoring the validation-framework idiom. Behavior is unchanged. (XSD content validation stays one recursive rule by a documented scope decision, since its constraints are interdependent through type resolution; Schematron already exposes its rules as composable `Validation<Node, Void>` values.)

### Added

- Conformance corpus harness (#105, Tier 2): the start of conformance-suite checking, expressed through the validation framework (the OpenAPIKit idiom). A `PureXML.Validation.ConformanceCase` is a `Validatable` named expectation (actual vs spec-authoritative expected output), and `Conformance.matchesExpected` is a `Validation<ConformanceCase, Void>` rule that emits one located `ValidationError` per diverging case, so a whole suite reports every failure at once with the case name as its coding path. Seeded with a Canonical XML 1.0 corpus (attribute ordering, empty-element expansion, comment removal, CDATA-to-escaped-text, processing instructions, namespace rendering) an XPath 1.0 core-function corpus, and an XSD datatype/facet corpus (length, range, pattern, enumeration, lexical space), a RELAX NG pattern corpus (text, optional, repetition, choice, ordered group, attribute, interleave, empty), an XSLT 1.0 transformation corpus (value-of, for-each, if, choose, sort, variable, format-number, apply-templates, call-template), an HTML5 tree-construction corpus (void elements, implied tag closing, case normalization, the adoption agency, entities), a Schematron corpus (assert, report, rule context), a C14N exclusive/2.0 corpus (unused-namespace dropping, render-at-use, whitespace trimming), an XPath axes/predicates corpus (descendant, ancestor, sibling axes, positional and attribute predicates, union), and a DTD content-model corpus (sequence, choice, occurrence indicators, mixed, EMPTY, ANY). The HTML corpus surfaced its first divergence (the fragment parser does not reconstruct active formatting elements like the document parser, tracked as #109). Growing the corpora against the official W3C/OASIS suites is the ongoing Tier-2 work.
- EXSLT extension functions (#105, Tier 3): the `common`, `math`, and `sets` EXSLT modules, dispatched by resolving a function's prefix to its namespace (so any prefix bound to an EXSLT namespace works). `math:min`, `math:max`, `math:highest`, `math:lowest`, `math:abs`, `math:sqrt` (with the EXSLT NaN rule for non-numeric nodes); `set:distinct`, `set:difference`, `set:intersection`, `set:has-same-node`, `set:leading`, `set:trailing` (by node identity and document order); `exsl:object-type`. `math:power` and the other transcendentals are omitted because they need a C math library, which the pure-Swift, Foundation-free target excludes; `exsl:node-set` awaits result-tree-fragment support.
- Canonical XML 1.1 (#105, Tier 3): a `Canonical.Options.canonical11` preset and a `mergeInheritedBase` option. When canonicalizing a document subset, the `xml:base` values of the apex's omitted ancestors are merged into the apex by RFC 3986 reference resolution (vs. 1.0's nearest-ancestor rule), the apex's own relative `xml:base` is resolved against that chain, and `xml:id` is no longer inherited; `xml:lang` and `xml:space` still inherit the nearest. A self-contained RFC 3986 resolver (scheme/authority/path parsing, path merging, dot-segment removal) backs the merge.
- Single-byte legacy encodings (#97): the byte decoder gains a table-based single-byte path and the full set of single-byte legacy encodings, selected by the XML declaration's `encoding` name for both the whole-buffer and streaming decoders: the complete ISO-8859 family (parts 2 through 16), Windows-1250/1251/1253/1254/1255/1256/1257/1258, and KOI8-R/U. Most are vendored verbatim from the authoritative `unicode.org` mapping files; ISO-8859-5/9/15 are derived exactly; Windows-1254 composes from Windows-1252. Multi-byte CJK encodings (#99) are tracked separately.

### Fixed

- The HTML fragment parser (`HTML.parse`) now reconstructs active formatting elements, matching the document parser and the HTML5 algorithm (#109, surfaced by the Tier-2 conformance corpus). When a formatting element is closed out of order it is re-opened for the following content, so `<b><i></b>X</i>` yields `<b><i></i></b><i>X</i>` (not `<b><i></i></b>X`), in both the fragment and document paths.
- XSD identity-constraint errors now locate the offending field, not just the element (#104): a single-field `key`/`keyref`/`unique` error extends the coding path with the field itself, an attribute (`... at path: list/item[2]/@id`) or a child element (`.../code`), resolved from the constraint's field XPath. keyref scope resolution is confirmed to resolve a key declared on an ancestor element (cross-scope), with a test. Full XSD qualified-node-set conformance for pathological multi-level same-name nesting remains part of the conformance-corpus work.
- XSD identity-constraint errors (`key`, `keyref`, `unique`) now carry a coding path locating the actual offending element, instead of always rendering "at root of document". The `IdentityValidator` walk threads a `[PathKey]` the same way the content-model validator does, and each error is located at the selected target node, so a duplicate-key failure reports "... at path: list/item[2]" and a dangling keyref "... at path: orders/line" rather than an empty path. This brings the identity-constraint rule into line with the validation framework's path-carrying contract, which every other rule already honored. The "no element declaration for the root" XSD error is likewise located at the root element, matching the namespace check beside it.
- A `<template>` element's flow content is now kept nested inside it (`<template><div>x</div></template>`) instead of being split out into the body (#83). `template` is built as body flow content rather than routed to the head.

### Added

- ISO-2022-JP decoding (#108, in progress): the byte decoder gains the WHATWG `iso-2022-jp` algorithm, selected by the `iso-2022-jp` declaration name. Unlike the other CJK encodings this one is stateful, escape sequences switch between ASCII, JIS X 0201 Roman (with the yen sign and overline), JIS X 0201 katakana, and the JIS X 0208 plane, which is resolved through the shared `jis0208` table (no new data). The streaming decoder now honors the declared encoding from the XML declaration (the libxml2 behavior), not only a byte-order mark, so the single-byte and multi-byte CJK decoders, including the stateful ISO-2022-JP whose mode is carried across reads, work over an incremental byte source; a test asserts streaming agrees with whole-buffer decode for a single-byte, a CJK, and an ISO-2022-JP document.
- EUC-TW decoding (#108): the byte decoder gains EUC-TW (CNS 11643), selected by the `euc-tw` declaration name, for both the whole-buffer and streaming decoders. ASCII passes through; a lead in `0xA1`-`0xFE` opens a two-byte plane-1 character; `0x8E` opens a four-byte form whose second byte selects the plane. CNS planes 1 and 2, which carry essentially all real-world EUC-TW text, are vendored from the ICU `euc-tw-2014` mapping (private-use fallbacks dropped); the rarely used planes 3-15 decode to the replacement character and are a documented follow-up.
- Streaming (reader-driven) DTD validation (#107, in progress): `PureXML.validate(streaming:dtd:)` and `PureXML.Validation.StreamingDTDValidator` validate a document against a DTD while it is pulled event by event (the libxml2 `xmlTextReader` validation model), holding only the open-element stack rather than the whole tree. Each element's content model and attributes are checked the moment it closes, by applying the exact per-element DTD rules to a shallow element synthesized from the streamed child names. Document-scoped ID/IDREF integrity is tracked in bounded sets (the identifier values, not the tree): a duplicate ID is reported at its repeat occurrence, and forward IDREFs resolve at the end of the stream. Streaming and tree validation report the same problems (a test asserts matching reasons), and errors carry a libxml2 `xmlGetNodePath`-style coding path. RELAX NG streaming is also available via `RelaxNG.validate(streaming:)`: the Brzozowski derivative is itself incremental, so it is driven directly from the event stream, retaining only the residual pattern (the `after`-threaded chain is the validation stack) and a light per-element frame for ignorable-whitespace handling; a differential test asserts it agrees with the tree engine across valid, invalid, whitespace, and mixed-content documents. XSD streaming is available via `Schema.Document.validate(streaming:)`: each element's type is resolved from its parent's content model (and `xsi:type` / `typeReference`) as it opens, and its attributes and content-model structure are checked shallowly as it closes (`ComplexValidator.validateShallow`), with a differential test asserting agreement with the tree validator. Wildcard `processContents` and substitution-group resolution in the streaming form stay on the tree validator.
- Output encoding (#106): `Serializer.serialize(_:encoding:)` and `PureXML.serialize(_:encoding:)` now emit bytes in a chosen encoding (the libxml2 `xmlSaveToFilename(..., encoding)` model), not only UTF-8. A new `PureXML.Parsing.ByteEncoder` covers the Unicode transformation formats, the single-byte legacy families (ISO-8859, Windows code pages, KOI8), and the multi-byte CJK encodings (Shift-JIS, EUC-JP, EUC-KR, GBK, GB18030, Big5). The CJK and single-byte inverses are built by running the existing, tested decoders over every valid byte sequence and recording the shortest sequence per scalar, so each encoder is by construction the exact inverse of its decoder (no new data, no separately maintained encode tables); GB18030's astral range uses the four-byte pointer formula. The declaration carries the encoding's canonical name, a UTF-16/32 stream is preceded by a byte-order mark, and any scalar the target encoding cannot represent is written as a decimal numeric character reference, so output always round-trips.
- Big5 (#103): the byte decoder gains the WHATWG `big5` algorithm, for both the whole-buffer and streaming decoders, selected by the `big5` declaration name (and the `big5-hkscs` / `cn-big5` aliases). A lead in `0x81`-`0xFE` followed by a trail in `0x40`-`0x7E` or `0xA1`-`0xFE` resolves through the index, covering Traditional Chinese and the HKSCS extensions including the astral CJK ideographs (Extension B and the Compatibility Supplement). Four pointers decode to a base letter plus a combining mark (a two-scalar sequence). The 18,590-entry index is vendored verbatim from the WHATWG `index-big5.txt`. Big5 completes the major CJK families libxml2 reaches through iconv (Japanese, Korean, Simplified and Traditional Chinese).
- Full GB18030 (#102): the byte decoder gains the GB18030 four-byte sequences on top of the GBK two-byte subset, for both the whole-buffer and streaming decoders, selected by the `gb18030` declaration name. A lead in `0x81`-`0xFE` followed by a digit opens a four-byte form whose pointer is mapped through the WHATWG `index-gb18030-ranges` linear ranges, reaching the supplementary planes (the `189000` range maps to `U+10000` and beyond). The 207 ranges are vendored verbatim from the WHATWG `index-gb18030-ranges.txt`. GB18030 is China's mandatory standard, supported in libxml2 through iconv.
- CJK multi-byte encodings (#99, in progress): the byte decoder gains a multi-byte path and the WHATWG **Shift-JIS** and **EUC-JP** algorithms, for both the whole-buffer and streaming decoders, selected by the XML declaration's `encoding` name. Shift-JIS covers ASCII, half-width katakana, and the JIS X 0208 plane; EUC-JP adds the `0x8E` half-width katakana and `0x8F` JIS X 0212 leads. EUC-KR (CP949/UHC) decodes Hangul and Hanja through the WHATWG `index-euc-kr`, and GBK (which also covers GB2312) decodes Chinese through the two-byte range of `index-gb18030` with `0x80` as the euro sign. The JIS X 0208/0212, CP949, and GBK indexes are all vendored verbatim from the corresponding WHATWG `index-*.txt` files. This completes the CJK multi-byte encodings.
- HTML named character references: the complete WHATWG named character reference set (#84), all 2,125 semicolon-form references including the astral mathematical alphanumerics and the 93 two-codepoint references, vendored verbatim from the authoritative `entities.json` (replacing the previous 16-entry stopgap). Decoding stays longest-match with an optional trailing semicolon, on top of the existing numeric-reference validation.
- HTML5 select content model (#83, stage 10): a `<select>` now follows the in-select rules. `<optgroup>` closes an open `<option>`, a nested `<select>` closes the open one rather than nesting, and an `<input>`/`<keygen>`/`<textarea>` closes the select and is placed after it. In the "in select in table" case, a table-structural tag (`caption`/`table`/`tbody`/`tfoot`/`thead`/`tr`/`td`/`th`) closes a select that is inside a table before being processed.
- HTML5 frameset documents (#83, stage 8): a `<frameset>` after the head now produces a frameset document whose `frameset` element replaces the body (`<html><head></head><frameset>...`), with nested framesets and `<noframes>` handled, and `<frame>` is now a void element (it no longer wrongly nests). An ordinary document still produces a body.
- HTML5 integration points (#83, stage 7): HTML content inside an SVG integration point (`foreignObject`, `desc`, `title`) is now parsed in the HTML namespace rather than SVG, so `<svg><foreignObject><div>` puts the `div` (and its descendants) back in HTML; re-entering `<svg>` inside an integration point switches back to the SVG namespace.
- HTML5 table foster-parenting (#83, stage 6): stray flow content inside a table is now moved out rather than nested in the table structure, matching the HTML standard. A non-table element or character data appearing while a `table`/`tbody`/`thead`/`tfoot`/`tr` is the open node is inserted immediately before the table (`<table><b>x</table>` -> `<b>x</b><table></table>`), while well-formed cell content is untouched.
- HTML5 SVG attribute-name case adjustment (#83, stage 5): an SVG attribute written in mixed case is restored to its canonical camel case in the tree (`viewbox` -> `viewBox`, `gradienttransform` -> `gradientTransform`, and the rest), applying only to elements in the SVG namespace. HTML attribute names are left as the tokenizer lowercased them. With this, SVG/MathML foreign content carries correct element and attribute names.
- HTML5 adoption agency algorithm and active formatting elements (#83, stage 4): misnested formatting tags are now recovered exactly as the HTML standard prescribes. Overlapping tags nest (`<b><i></b></i>` -> `<b><i></i></b>`), content after an out-of-order close is re-wrapped by reconstructing the active formatting elements (`<b><i></b>X</i>` -> `<b><i></i></b><i>X</i>`), and a block inside a formatting element reparents through the furthest-block path, including the canonical `<p>1<b>2<i>3</b>4</i>5</p>` -> `<p>1<b>2<i>3</i></b><i>4</i>5</p>`.
- HTML5 SVG element-name case adjustment (#83, stage 3): an SVG element written in mixed case (which the tokenizer lowercases) is restored to its canonical camel case in the tree, so `<foreignObject>`, `<linearGradient>`, `<clipPath>`, and the rest carry their correct SVG names. Applies only in the SVG namespace; same-named HTML elements keep their lowercased name.
- HTML5 foreign content (#83, stage 2): an `<svg>` or `<math>` element and all of its descendants now carry the SVG (`http://www.w3.org/2000/svg`) or MathML (`http://www.w3.org/1998/Math/MathML`) namespace on their `QualifiedName`, so foreign elements are distinguishable from same-named HTML; ordinary HTML content (including content after a closed `<svg>`) stays in no namespace. (SVG/MathML element- and attribute-name case adjustment, and HTML integration points, are a later refinement.)
- HTML5 table tree construction (#83, stage 1): a `<table>` written without its section and row wrappers now nests correctly. A `<tr>` directly inside a `<table>` gets an implied `<tbody>`, a `<td>`/`<th>` gets an implied `<tr>` (and section), consecutive rows share one implied `<tbody>`, and an explicit `<thead>`/`<tbody>`/`<tfoot>` is not duplicated, all inside an open table only.
- HTML tokenizer correctness (#84, partial): numeric character references are now range/surrogate-validated (zero, surrogates, and values above U+10FFFF yield U+FFFD) with the Windows-1252 C1 fixup table (`&#x80;` -> euro, etc.); named references are decoded by longest match with or without a trailing semicolon; a literal NUL byte becomes U+FFFD; RCDATA elements (`title`, `textarea`) decode character references while raw-text elements (`script`, `style`) take their content verbatim; and a single leading newline after `<textarea>` is stripped. (The full ~2,000-entry named-entity table remains deferred to vendoring from the authoritative WHATWG data, the same policy as the legacy encodings.)
- HTML conformance validator in the composable `Validation` idiom. `PureXML.HTML.validationErrors(in:)` (backed by `PureXML.Validation.HTML`) judges a parsed tree against the intrinsic HTML5 content-model invariants as named, removable, isolation-testable `Validation` rules, the same idiom as the DTD/XSD/structural validators: `voidElementsAreEmpty` (void elements carry no content), `requiredParent` (`li`/`td`/`option`/... appear inside an allowed parent, with the allowed parents named in the finding), and `uniqueIdentifiers` (`id` values are unique). Failures are located `ValidationError`s; this is the validation layer HTML previously lacked, so every parsing/schema subsystem now exposes its conformance checks as composable rules.
- XInclude range inclusion (#87), completing the XInclude audit. An `xi:include` whose `xpointer` selects a range (`xpointer(range(...))`, `range-to`, or `string-range`) now includes that range's content: when no node-selecting scheme matches, the processor falls back to the XPointer range model and substitutes each range's spanned nodes (or the matched text for a `string-range`).
- XPointer `range()` model (#88), completing the XPath/XPointer audit. `PureXML.XPointer.evaluateRanges(_:over:)` (and `Pointer.evaluateRanges(over:)`) evaluate the range forms inside an `xpointer()`/`xpath1()` scheme: `range(expr)` (the covering range of each location), `start/range-to(end)` (one range spanning from the first location of `start` to the first of `end`, the sibling run when they share a parent), and `string-range(location, "search"[, offset[, length]])` (a character range per occurrence, with the XPointer offset/length adjustment). Each `Range` materializes to the whole `nodes` it spans and the `text` it covers, and `xmlns()` bindings apply to the range parts that follow, so this also unblocks XInclude range inclusion (#87).
- C14N node-subset canonicalization and Canonical XML 2.0 parameters (#85), completing the canonicalization audit. `Canonicalizer.canonicalize(_ subtree: TreeNode)` canonicalizes a fragment in place: the apex element renders the namespace context in scope from its omitted ancestors and inherits their `xml:base`/`xml:lang`/`xml:space` when it does not set them, so a signed fragment is independent of where it sat. `canonicalize(_:including:)` canonicalizes a node-set selected by a `TreeNode` predicate (XPath/position-based selection): an excluded element's tags are omitted but its selected descendants are kept and re-declare their in-scope namespaces. `Options.prefixRewrite = .sequential` rewrites every prefix to a canonical `n0`/`n1`/... in document order (eliminating the default namespace and placing declarations at first use), and `Options.qnameAwareLabels` extends that rewrite into QName-valued attributes and elements, so documents differing only in prefix spelling canonicalize to identical bytes.
- Serialization `textEscaping` round-trip option (#91), completing the serialization audit. `Options.textEscaping` defaults to `.standard` (escape only `&`, `<`, `>`); `.roundTrip` also escapes a carriage return as `&#xD;` in text and CDATA-as-text output, so a literal `\r` survives the parser's end-of-line normalization and the document round-trips byte for byte. (The CDATA-section vs escaped-text toggle, `cdataAsText`, was already present.)
- DOM tree: first-class doctype, entity-reference, and namespace nodes, plus `ownerDocument`, `adopt`, and `importNode` (#90), completing the tree-model audit. `TreeNodeKind` gains `.doctype`, `.entityReference`, and `.namespace`, each with a factory (`TreeNode.doctype(name:publicID:systemID:internalSubset:)`, `.entityReference(_:children:)`, `.namespace(prefix:uri:)`) and typed accessors; doctype and namespace nodes drop out of the content value-`Node` projection while an entity reference splices its replacement into place. `ownerDocument` derives the owning document from the parent chain; `adopt` and `importNode` move or copy a subtree into another document, re-declaring every namespace it relied on from an outer scope so the result is self-contained.
- Schematron `key()`, `document()`, and `current()` in tests (#80), completing the Schematron audit. Test, let, and message expressions can now resolve nodes through `xsl:key` declarations, load an external document for cross-document checks (via an injected `documentLoader`), and refer to the rule context node with `current()`.
- RELAX NG compact `>>` follow-annotations (#79), completing the RNC syntax. A `>>` annotation after a pattern (a foreign element name with optional `[ … ]` content) is skipped, chaining and combining with leading `[ … ]` annotations; both carry no schema semantics. (Namespace declarations inside annotations are already dropped by the annotation skipper.)
- XSLT `document()` fragments and base-URI resolution (#82), completing the XSLT function/output audit. A `#fragment` selects a subset of the loaded document via XPointer, a node-set first argument unions the documents named by each node, and a relative URI is resolved against a caller-supplied `baseURI` (also applied to `xsl:include`/`xsl:import`).
- XSLT result-tree fragments usable as node-sets (#82). An `xsl:variable` with a body now binds a queryable document fragment instead of a plain string, so `count($rtf/*)`, `$rtf/child`, and `xsl:for-each select="$rtf/..."` work; it still has its concatenated text as a string value.
- XSLT `xsl:output cdata-section-elements` (#82). The text content of the named result elements is emitted in `<![CDATA[…]]>` sections instead of escaped, leaving nested elements and other elements unaffected.
- XSLT `xsl:output` `doctype-public`/`doctype-system` (#82). When either is set, a `<!DOCTYPE>` for the result's root element (PUBLIC when both are given, SYSTEM otherwise) is emitted before the serialized output, for XML and HTML methods.
- XSLT `key()` over a node-set second argument (#82). `key(name, node-set)` (including `key('k', .)`) now unions the matches for every node's string value and de-duplicates, rather than using only the first node's string value.
- XSLT `method="html"` output (#82). An `xsl:output method="html"` result is now serialized by the HTML rules (void elements like `<br>` emitted without a self-closing slash, raw-text elements like `<script>`/`<style>` left unescaped) instead of as XML.
- XSLT `xsl:sort case-order` (#82). When `case-order="upper-first"`/`"lower-first"` is set, the sort comparison is case-insensitive with the case used only to break ties among otherwise-equal strings; without it the default codepoint order is kept.
- XSLT functions `generate-id`, `system-property`, `element-available`,
  `function-available`, and an `unparsed-entity-uri` stub (#82). `generate-id`
  returns a stable per-node identifier (the context node when no argument is
  given, the empty string for an empty node-set); `system-property` reports the
  XSLT version (1.0) and vendor; the `*-available` functions answer against the
  set of implemented instructions and functions.
- XSLT `xsl:namespace-alias` (#81), completing the XSLT top-level-element audit. A
  literal result element (and its attributes) in a stylesheet namespace bound by
  `stylesheet-prefix` is rewritten on output to the namespace and prefix bound by
  `result-prefix` (`#default` supported), so a stylesheet can emit literal `xsl:`
  elements. Folded across `xsl:include`/`xsl:import`.
- XSLT `xsl:decimal-format` (#81). `format-number` now honors named and default
  decimal formats: the decimal separator, grouping separator, percent, minus
  sign, zero-digit (so non-Latin digit sets render), NaN, and infinity symbols
  are taken from the chosen `xsl:decimal-format`, both in the picture and the
  output. Folded across `xsl:include`/`xsl:import`.
- XSLT `xsl:fallback` (#81). An unrecognized XSLT element instantiates its
  `xsl:fallback` children in its place (forwards-compatible processing), or is
  dropped when it has none; a fallback under a supported instruction is ignored.
- XSLT `xsl:apply-imports` (#81). Re-applies templates to the current node in the
  current mode, considering only templates of lower import precedence than the
  one being instantiated (so an overriding template can extend the imported one),
  falling back to the built-in rule when none match.
- XSLT `xsl:attribute-set` (#81). Named attribute sets are applied to a literal
  result element or `xsl:element` via `use-attribute-sets`; sets may include other
  sets (recursively, with a cycle guard), set attributes are lowest precedence so
  the element's own attributes override them, and same-named attributes collapse
  to the last. Folded across `xsl:include`/`xsl:import`.
- XSLT `xsl:message` (#81). The message body is instantiated as diagnostic text;
  `terminate="yes"` aborts the transformation with that text as an
  `XSLTError.terminated`, and processing stops at that point. A non-terminating
  message produces no result-tree output.
- XSLT `xsl:strip-space` / `xsl:preserve-space` (#81). Whitespace-only text nodes
  are removed from the source tree for elements named by `strip-space` before
  transformation, with `preserve-space` and a more specific name test winning over
  `*`, and `xml:space="preserve"` on a source element or ancestor overriding the
  stripping. Folded across `xsl:include`/`xsl:import`.
- DTD located content-model errors. An element whose children break its content
  model now names each stray child individually (`element <x> is not allowed in
  <r>`), and reports a pure order/count violation once with the allowed elements
  as a hint (`… do not match its content model; allowed: <a>, <b>`), instead of a
  single opaque message, matching the editor-grade diagnostics of the other
  validators.
- XSD located content-model errors. A content-model violation is now placed at
  the offending child with a recovery hint naming what was expected there
  (`element 'x' is not allowed here; expected <b>`, `content is incomplete;
  expected <b>`), instead of one opaque "content does not match the content
  model" per element. An `xs:all` group recovers past each stray child and
  reports every missing required member, and well-placed children are still
  validated for their own content, so an editor sees every problem at once. This
  brings XSD content validation to the same located, recovering standard as the
  RELAX NG, DTD, and Schematron validators.
- RELAX NG located, recovering validation errors (#79). Alongside the boolean
  `validate(_:)`, `RelaxNG.errors(in:)` now reports every way a document fails the
  schema as individual located errors (each with a coding path), recovering past
  each failure so an editor can surface all of a faulty document's problems at
  once rather than only the first. Errors carry recovery hints (`expected <a>,
  <b>`) naming the element types accepted at the failure point, and distinguish
  unexpected elements, invalid or missing attributes, invalid text/datatype
  content, and missing required content. A datatype mismatch quotes the offending
  value and names the expected type (`'abc' is not a valid integer`), and a value
  mismatch quotes both the actual text and the required literal. An attribute
  failure distinguishes an undeclared attribute from a declared one with a bad
  value, quoting the value and naming its type. `RelaxNG.validation()` exposes the schema
  as a `Validation<Node, Void>`, so RELAX NG composes with the same validation
  framework as the XSD, DTD, and Schematron rules. The boolean engine remains the
  authority on validity; the walk only places and explains the failures.
- XML catalog group-level `prefer` (#86). A `prefer` attribute on a `group` (or a
  nested `catalog`) now overrides the catalog-wide preference for the `public`
  entries inside it, inherited through nested groups. Resolution of an external
  identifier consults each public entry's own effective preference, so two entries
  in one catalog can prefer differently. A system match still always wins.
- Schematron abstract patterns (#80). A `<pattern abstract="true">` is a template
  whose rule queries carry `$name` references; a `<pattern is-a="…">` with
  `<param name= value=>` children instantiates it, substituting each parameter
  into the template's `context`, `test`, `<let>` value, and `<value-of select=>`
  in a single pass that never rescans a substituted value or lets a short name
  capture a longer one. The template itself contributes no rules, and `$name`
  references that are not parameters (ordinary `<let>` variables) are preserved.
- RELAX NG conformance: `datatypeLibrary`, value-space `<value>`, name-class
  subtraction, and compact-syntax breadth (#79). The in-scope `datatypeLibrary`
  is now inherited from the nearest ancestor; the default library defines only
  `string` and `token`, the W3C XML Schema library defines the full built-in set,
  and a type no in-scope library defines is an unknown datatype, so its `<data>`
  or `<value>` matches nothing rather than validating silently. A `<value>`
  carries its datatype and compares in that type's value space, so `1` equals
  `01` and `1.5` equals `1.50`, booleans treat `1`/`true` and `0`/`false` as
  equal, and `string`/`token` compare by their whitespace-normalized form. A new
  `nsNameExcept` name class backs `<nsName>` with `<except>` and the compact
  `prefix:* - name` subtraction. The compact parser also skips `[ … ]`
  annotations, treats `div { … }` as transparent grouping, and folds `~` string
  concatenation.
- XSLT template parameters and modes (toward full parity, #61). `xsl:param`
  declarations (with defaults), `xsl:with-param` on `apply-templates` and
  `call-template`, and `mode` on templates and `apply-templates` are now honored:
  a passed parameter overrides the declared default, and a mode routes nodes only
  to templates declared in that mode (the built-in rules recurse in the same
  mode).
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
