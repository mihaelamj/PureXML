# Changelog

All notable changes to PureXML are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Scanner-side validity findings are now located structured values (validation-framework audit follow-up): `DocumentType.validityFindings` carries `ValidityFinding` values (reason plus the declared name they are about) instead of strings, `DTDSchema.declarationErrors` holds ready `ValidationError`s, and every declaration-level finding renders at its declaration's coding path (`x`, `r/@a`) instead of "at root of document", matching the XSD consistency-errors precedent. Finding texts are unchanged.

### Added

- Globals, prefix wildcards, fifteenth xalan burn-down (#130): a top-level variable now evaluates with every previously evaluated global in scope, so a variable whose body references an earlier top-level param (directly or via call-template) resolves; same-name globals resolve by import precedence (folds happen in precedence order and the last same-name entry wins, so a later sibling import beats an earlier one and the importing sheet beats both); the stylesheet fold uniformly favors later contributions for attribute-set definitions, decimal formats, namespace aliases, and output settings, matching the post-order precedence model; and the XPath compiler accepts the `NCName:*` name-test form, matching any name in the prefix's namespace (bound by URI, falling back to the in-document prefix string) at its -0.25 default priority, so `@ped:*` outranks `@*`. Three unit tests pin the behaviors. Baseline 144 to 134 (variable 10 to 5, conflictres 8 to 5).
- Import precedence and relative composition, fourteenth xalan burn-down (#130): import precedences are assigned in post-order over the import tree, so sibling imports are distinct (later higher) and every unit sits above its own imports; apply-imports searches only the current template's stylesheet's own import subtree per 5.6 (templates carry their unit's precedence range), falling back to the built-in rule when that unit imports nothing; an included stylesheet's declarations join the including unit at its precedence while its imports join the import list; and include/import hrefs resolve against the including stylesheet's own URI, so nested relative chains load correctly. Also fixed along the way: an included document's tree was only weakly referenced once flattened, so its ancestor chain (xmlns declarations, exclusions in scope) could disappear before its templates were parsed. Two unit tests pin apply-imports scoping and relative chains. Baseline 159 to 144 (reluri 11 to 3, impincl 9 to 2).
- Attribute sets, copied namespaces, html booleans, loader entities, thirteenth xalan burn-down (#130): same-name `xsl:attribute-set` declarations merge as ordered definitions per 7.1.4 (each expands its used sets before its own attributes, a later definition's attributes winning); `xsl:copy` of an element carries the source element's in-scope namespace nodes per 7.5 (the fixup pass drops result-redundant ones); the namespace fixup lets a carried attribute prefix shadow an inherited binding locally (matching the source document's shape) unless the element's own name relies on it; the html method minimizes boolean attributes whose value repeats their name (CHECKED="CHECKED" serializes as CHECKED); and external DTDs and entities referenced by the stylesheet or source now resolve through the transform's document loader, the same channel as document(). Four unit tests pin the new behaviors. Baseline 174 to 159 (attribset 13 to 4, copy 12 to 7).

### Fixed

- format-number and xsl:number no longer trap on extreme values (#130 critic loop): format-number of a value at or beyond 2^53 rendered through an unguarded Double-to-Int conversion, a fatal trap reachable from user data (format-number(99999999999999999999 * 99999999999999999999, '#,##0') crashed the host); a fraction picture with more than 15 places overflowed the scale conversion the same way; and xsl:number value= beyond 2^53 trapped identically. Digit extraction now clamps fraction places to 15 (the 2^53 exactness bound), pads back to the picture's requested minimum, renders out-of-range integers through the exponent expander (digits stay exact), and xsl:number falls back to plain XPath number rendering outside [1, 2^53). Regression tests cover all three paths.

### Added

- Critic-loop hardening of the xalan burn-down (#130): raw-output marker handling is now gated on the stylesheet actually mentioning `disable-output-escaping`, so a source document that happens to contain the private-use marker characters U+E000/U+E001 passes through every transform untouched (previously they were stripped, and text between them unescaped, unconditionally), and the text output method only removes markers without "unescaping" content that was never escaped; the pattern-matching function table is built once per transform instead of once per (template, node) membership test; and the d-o-e, CDATA "]]>" splitting, simplified-syntax, html default-method/META, per-document key(), and attribute-axes behaviors gain focused unit tests that run in CI without the opt-in corpus (eight new tests).
- Following/preceding from attribute nodes, twelfth xalan burn-down (#130): the following and preceding axes now work from attribute and namespace starts, anchored at the owner element per the XPath 1.0 document order (an attribute follows its element and precedes its children, and has no descendants of its own). Baseline 182 to 174 (axes 16 to 8).
- Keys per document, in document order, eleventh xalan burn-down (#130): `key()` resolves its index against the current node's own document (built lazily per document root, so keys work inside document() trees), a node-set `use` expression indexes the matched node under every member's string value, and key() results return in document order regardless of the lookup value order. Baseline 187 to 182.
- Sort keys in context and cross-document template matching, tenth xalan burn-down (#130): xsl:sort keys are computed once per node with the node's own evaluation context (its position and size in the selection, the caller's variables, functions, and namespace bindings), so position()-based and variable-referencing keys work, and NaN keys order before every number under data-type="number" (the Xalan order); match patterns evaluate over the matched node's own document rather than the transform source, so templates match nodes loaded through document() (the match cache keys include the document identity). Baseline 204 to 187 (sort 18 to 11, mdocs 14 to 6).
- Prolog and CDATA conformance, ninth xalan burn-down (#130): the XML declaration precedes the document type declaration; a public-only doctype is emitted by the html method (16.2) and ignored by the xml method, which requires `doctype-system` (16.1); the simplified stylesheet syntax of 2.3 (a literal result element carrying `xsl:version`) compiles as a single match="/" template; and cdata-section-elements text containing "]]>" splits across section boundaries so no section holds the terminator. Baseline 218 to 204 (output 34 to 20).
- Stylesheet namespace resolution, eighth xalan burn-down (#130): a template carries the xmlns bindings in scope at its stylesheet element, and they flow into its match pattern (the match cache keys on pattern plus bindings) and every expression evaluated while it is instantiated, so `match="baz2:doc"` and `select="local-name(baz2:b)"` resolve the prefix against the stylesheet and match by namespace URI; with bindings supplied the XPath 1.0 rule applies exactly, an unprefixed name test selecting only the null namespace. The instruction-scope namespace capture includes the default declaration, so `xsl:element` honors an in-scope `xmlns="uri"` for its unprefixed created names, an in-scope `xmlns=""` keeps them namespace-free (undeclared in the result when an inherited default would capture them), and an unusable created name (`:foo`) drops the wrapper and keeps the content, the Xalan recovery. Baseline 263 to 218 (namespace 41 to 13, axes 16, sort 18, output unchanged at 34, the rest spread).
- Keys, ids, and doctyped sources, seventh xalan burn-down (#130): `key()` and `document()` read the string value of attribute and namespace node arguments instead of dropping them (the Muenchian grouping idiom works); match patterns evaluate with the XSLT function table, so `key('k', 'v')` and `id('x')` patterns match (a key/id pattern branch is also no longer prefixed with `//`); and the XSLT entry points parse sources, stylesheets, and `document()` loads with doctypes allowed, which the conformance corpora use throughout. Baseline 292 to 263 (idkey 39 to 16, the rest spread).
- Templates over attribute and namespace nodes, sixth xalan burn-down (#130): xsl:apply-templates and xsl:for-each now keep attribute and namespace nodes in their selections instead of dropping them at the tree-node conversion. The evaluation context carries the non-tree current node (its owner element backs the tree-only machinery), XPath evaluation and current() start from it, match patterns select attribute nodes (the match cache keeps attribute identities, owner plus name, alongside tree identities), the built-in rules copy an attribute's or namespace's value as text, xsl:copy copies the focused attribute or namespace declaration itself, and an attribute result arriving after element content is ignored (the XSLT recovery). Sorting and apply-imports work over the generalized node kind. Baseline 352 to 292 (axes 35 to 16, copy 29 to 16, attribset 18 to 13, the rest spread).
- Output methods in depth, fifth xalan burn-down (#130): `disable-output-escaping` on xsl:value-of and xsl:text (raw text travels bracketed by private-use sentinels and the serializer's escaping is undone after the fact; a string extracted from a result tree fragment loses the markers per 16.4, so the variable round-trip case re-escapes); the default output method is html when the first result element is named html with a null namespace (16.1); the xml method writes the XML declaration unless `omit-xml-declaration="yes"` (the spec default, with the caller's emit options as fallback only on explicit stylesheet silence); the html method injects `META http-equiv="Content-Type"` into head (16.2), keeps SCRIPT/STYLE raw and void elements end-tag-free case-insensitively, and escapes U+00A0-U+00FF to the HTML 4.01 Latin-1 entity names. Whitespace-only detection in stylesheet/source stripping now means XML whitespace only, so an NBSP-only text node survives. The conf comparison treats whitespace adjacent to tag boundaries as layout for non-canonical comparisons. Baseline 371 to 352 (output 49 to 30).
- Literal result element namespace copying, fourth xalan burn-down (#130): a literal result element now copies its in-scope namespace declarations to the result per 7.1.1, minus the XSLT namespace and the namespaces of the prefixes listed in `exclude-result-prefixes`/`extension-element-prefixes` in scope (`#default` included); an aliased stylesheet namespace declares its result prefix and URI instead. The namespace-fixup pass drops any declaration that repeats an inherited binding, so the copied nodes do not redeclare on every descendant, and created names now reuse the stylesheet's own prefixes (`anamespace:Attr1` rather than `ns0:Attr1`). `xsl:output indent="yes"` switches to the corpus golds' Xalan indentation form: children on their own lines with no leading spaces. Two unit expectations updated to the spec behavior (a literal element under stylesheet-level declarations carries them; collapsed alias+result declarations). The xalan baseline drops from 446 to 371 (namespace 89 to 42, output 50 to 49 and others spread across categories).
- format-number picture parsing in full, third xalan burn-down (#130): the picture now parses JDK DecimalFormat-style into literal prefix/suffix affixes around the number part, the negative subpattern after the pattern separator (its affixes apply; without distinguishing ones the minus sign still prefixes, the Xalan resolution, which also covers colliding decimal/grouping separators by reading every occurrence as grouping), per-mille (with a custom symbol via the new `per-mille` attribute) and percent as multipliers kept literally in the output, the grouping size taken from the last grouping separator's distance to the decimal point instead of a fixed 3, and the generic currency sign U+00A4 rendering as this processor's en-US `$`. Digit extraction is rewritten over one scaled rounding plus pure integer arithmetic, so 0.4812 renders 4812 rather than re-accumulating float error per digit. The xalan numberformat category drops 30 to 1 (the survivor is a namespace-copy case); baseline 475 to 446.
- Full xsl:number per XSLT 1.0 section 7.7, second xalan burn-down (#130): `level` single/multiple/any with `count` and `from` as real patterns matched through the transform's match cache (default count: same node type and expanded name; single finds the nearest matching ancestor-or-self and numbers it among matching preceding siblings, multiple numbers every matching ancestor-or-self outermost first, any counts matching nodes at or before this one in document order with `from` as the boundary, always yielding a number so an unmatched count renders 0); the `value` expression evaluates and rounds, bypassing formatting below one; and the full format-token engine (leading/trailing punctuation, alternating alphanumeric tokens and separators with last-token and last-separator reuse, zero-padded decimal widths, `a`/`A`/`i`/`I` and the Greek alphabetic sequence, `grouping-separator`/`grouping-size` digit grouping). A single/multiple level whose count matches nothing renders as the empty string, punctuation included. The xalan baseline drops from 557 to 475 (numbering 84 to 7, the rest pattern-engine prefixed/key/id cases).
- `document()` is stable per transform (#130): the same URI reference now returns the identical document object across calls within one transform, per the XSLT `document()` definition, via a per-transformer document cache; previously each call re-parsed, so node identity, and with it `generate-id()` uniqueness against live nodes, could be violated when an address was reused (the idkey49 flake).
- XSLT namespaced name creation and result fixup, first xalan burn-down (#130): xsl:attribute and xsl:element honor the `namespace` attribute and resolve a prefixed `name` against the instruction's own in-scope stylesheet declarations (7.1.2/7.1.3, captured at parse time so AVT names resolve correctly); xsl:copy applies `use-attribute-sets`; and a namespace-fixup pass runs over the result tree before serialization, declaring every namespace a created element or attribute name carries, reusing an existing binding for the same URI or generating `ns0`, `ns1`, ... prefixes when the carried prefix is absent or taken, and undeclaring an inherited default namespace that would capture an unqualified name. The xalan baseline drops from 604 to 557 (attribset 52 to 20, namespace 123 to 92, axes 68 to 35); one namespace-alias unit test updated to expect the now-declared result namespace.
- XSLT 1.0 conformance runner over the Apache xalan-test corpus (#122, #130): the de facto OASIS-era suite (1690 gold-bearing cases across 36 categories) runs opt-in via XALAN_TS_ROOT, never vendored. Comparison is deliberately normalized: outputs that parse as XML compare by canonical form (Xalan's indentation is not normative), others with whitespace runs collapsed. First measurement: 1086 pass; the 604 known failures are carried exactly in Tests/Fixtures/xalan-baseline.txt, asserted in both directions (a fixed case must leave the file, a regression shows as a new failure). The top burn-down classes by count: namespace handling (123, led by namespaced xsl:attribute creation), xsl:number depth (85), axes corners (68), output/serialization options (55), attribute sets (52), id()/key() (41).
- RELAX NG schema-correctness validation (#131): a schema document is now validated before any pattern interpretation, in three layers. The grammar check (section 3) rejects unknown or misplaced elements, illegal unqualified and RELAX NG-namespace attributes, wrong child arity, stray text, malformed or undeclared-prefix QNames, non-URI datatypeLibrary values (absolute, fragment-free, valid percent escapes), fragment-carrying hrefs, the 4.16 except restrictions (anyName/nsName inside excepts, propagated through choice), and the xmlns name prohibitions including the ns-attribute and except-mention forms. The compiler checks reject combine conflicts and double combine-less defines (4.17), unresolved refs and parentRef without a parent, startless grammars, include/externalRef self-reference, include overrides with nothing to override, non-grammar include targets (loaded documents are grammar-checked too), unknown datatypes, and params against the built-in library. The restrictions checker (4.19, 7.1-7.4) runs over the compiled algebra after 4.20/4.21 normalization (notAllowed/empty operands simplify away first; recursion detection deliberately precedes it): prohibited paths under attribute, oneOrMore-group, list, and in start; computable content types; duplicate attributes by representative-name overlap; infinite-name-class attributes outside oneOrMore; and the interleave text/element constraints. The spec suite's incorrect class drops from 213 compiling to 7, all pre-Fifth-Edition name-class cases (the xmltest-141 class, count asserted), with zero correct-schema or instance regressions. Two leniency tests updated to the spec behavior (double combine-less defines and unknown datatypes are schema errors).
- RELAX NG QName values, instance level clean (#131): `<value type="QName">` compiles to its (namespace, local-name) value pair via the schema's xmlns/ns scope, and the derivative engine threads the instance element's in-scope namespace bindings down to value comparison (in both the tree walk and the streaming state, whose frames now carry their bindings), so an instance QName resolves its prefix, or the default namespace when unprefixed, against the instance document itself; an unbound prefix matches nothing. The streaming path also gains the tree walk's empty-element rule. With this the spec suite's instance level is fully clean: valid 289/289 accepted and invalid 291/291 rejected; only the asserted schema-correctness class remains.
- RELAX NG grammar scoping and include depth, third burn-down (#131): each `grammar` element opens its own define scope (names are scope-mangled in the flat table, so nested grammars do not collide) and `parentRef` reaches the enclosing scope; `include` is transitive (an included grammar's own includes merge first) and a define carried by the include element replaces the included grammar's same-name define (the 4.7 override); `div` wrappers flatten into their grammar while still contributing ns/datatypeLibrary inheritance (4.11); `value` text is kept untrimmed so whitespace-preserving datatypes compare exactly (6.2.9); and `dataExcept` recurses through choice patterns. The spec suite is now clean except one class: valid 286/289 and invalid 287/291, with all six remaining instance cases the QName datatype (its value space needs prefix resolution in both the schema and instance contexts), plus the asserted schema-correctness item.
- RELAX NG namespaces and semantics, second burn-down (#131): the compiler now implements `ns` inheritance and the QName form of names (4.9-4.10: `ns` walks ancestors and crosses include/externalRef document boundaries; `name="eg:foo"` and `<name>eg:foo</name>` resolve their prefix against the schema's in-scope xmlns declarations; the `name=` shorthand on an attribute stays namespace-less rather than inheriting), an `include` brings in the included grammar's `start` with an include-level override honored (4.7), multiple `<start>` elements combine like defines and a single define or start may omit `combine` while still merging by the named method (4.17), `<data>` supports `<except>` via a new `dataExcept` pattern in the derivative engine (4.12), an empty element matches a data/value pattern whose lexical space admits the empty string (Clark's empty-text rule), and a whitespace-only attribute value matches a pattern that matches empty. Spec-suite baselines tighten from valid 242/289 to 274/289 and invalid 278/291 to 279/291; the name-class and tree-helper sections split to their own files for the length caps.
- RELAX NG simplification, first burn-down (#131): foreign-namespace elements are stripped before pattern interpretation (4.1: only RELAX NG-namespace elements are schema content; a namespace-less element counts only inside a fully unqualified schema), name/type/combine attribute values are whitespace-trimmed (4.2), and include/externalRef hrefs resolve against the xml:base attributes in scope and the loaded document's own URI (4.5, reusing the RFC 3986 resolver), with the document base threaded through nested loads and visited-tracking keyed on resolved hrefs. Spec-suite baselines tighten: valid 242/289 accepted (from 233), invalid 278/291 rejected.
- RELAX NG spec test suite runner (#122, #131): James Clark's spectest.xml (385 cases, distributed with jing-trang) runs via an opt-in RNG_TS_ROOT runner, never vendored; the manifest is parsed with PureXML itself, nested testSuite scopes thread their resource/dir definitions into the compiler's loader, and each case asserts compile/reject for the schema plus accept/reject per instance. First measurement, carried as exact baselines: every correct schema compiles and most instances behave (valid 233/289 accepted, invalid 277/291 rejected), while schema-correctness validation is absent (all 213 incorrect schemas compile, count asserted exactly). The burn-down classes are recorded in the runner: schema validation against the RELAX NG grammar and the 4.16-4.18 restrictions, foreign-namespace stripping (4.1), xml:base-aware include/externalRef resolution (4.5), and the section 6 compatibility datatypes.
- Canonical XML 1.0 spec-example vectors (#122, #132): the worked examples of the C14N 1.0 Recommendation's section 3 run as input/expected-output tests (cited per example; used under the W3C Software and Document License), all six passing: top-level PIs/comments with and without comments mode, whitespace preservation, start/end tags with attribute sorting and DTD defaults, character modifications and references, entity expansion, and UTF-8 output from legacy-encoded input. The vectors exposed three real conformance fixes: top-level siblings in the canonical form are now separated by single line feeds; an empty default-namespace declaration renders only when it undeclares a rendered non-empty default (superfluous `xmlns=""` is dropped, inclusive mode); and the text/attribute escape loops iterate Unicode scalars, so a carriage return that grapheme-clusters with a following line feed still escapes to `&#xD;` (the #135 class, surfacing in output rather than lexing).
- Scalar-level lexing (#135): the reader now buffers exactly one Unicode scalar per element (multi-scalar graphemes from any source are split, string input iterates scalars directly), so a combining mark directly after an ASCII delimiter can no longer merge with it into one Swift grapheme cluster and XML's scalar-defined name productions classify correctly: U+06D6 lexes as a Fifth Edition PI-target NameStartChar, ZWNJ/ZWJ attribute names parse, and U+309A markup from entity expansion forms a real element. The replacement-text, content-model, and ATTLIST sub-scanners and the entity-literal validator go scalar-level the same way, while grapheme clusters reassemble naturally wherever scanned text is appended to a String (asserted by test). This clears the last eduni baseline (now empty), grows the IBM pre-5e class from 279 to 300 exactly as the Fifth Edition prescribes, and, combined with the EDITION="1 2 3 4" exclusions the xmltest manifest itself carries for cases 140/141, empties the xmltest deviation baseline entirely: every xmlconf case applicable to a Fifth Edition, namespace-aware processor now passes.

- Strict internal-subset profile (#128): `Limits(strictInternalSubset: true)` holds the internal DTD subset to the letter of XML 1.0, rejecting conditional sections and parameter-entity references inside markup declarations (entity values, content models, ATTLIST bodies), both of which PureXML otherwise supports as features; DeclSep references between declarations and `%name;` inside quoted attribute defaults (AttValue, where `%` is literal) stay legal, and defaults are unchanged. The xmltest runner opts in, taking its baseline from 181/186 to 185/186 with one remaining documented deviation: case 141, which expects pre-Fifth-Edition name-character classes.
- Per-entity base-URI tracking (#138): a relative system identifier declared inside an external entity now resolves against that entity's own URI (RFC 3986, reusing the C14N resolver), so nested external entities find their siblings; `ExternalID` gains an optional `base` and a `resolvedSystemID`, the DTD scanner threads the current entity's URI through external-subset and parameter-entity scans, and resolvers receive the already-merged identifier (raw identifiers unchanged when no base applies). Clears eduni errata-2e/E18; the eduni baseline now holds only the #135 grapheme-lexing class.
- Encoding-declaration contradictions are fatal (#137, 4.3.3): a document whose XML declaration names a 16- or 32-bit encoding over BOM-less 8-bit bytes is rejected; a BOM followed by a declaration outside its family (a UTF-8 BOM with `encoding='iso-8859-1'`, a UTF-16 BOM with an 8-bit name) is rejected, with the declaration read through the BOM's own byte pattern; and an external entity whose text declaration names a higher XML version than the document's is refused (errata E38), in both the external-subset and external-entity paths. The eduni not-wf baseline is now completely empty.
- Namespaces 1.0 constraints (#136): the namespace layer now enforces the binding rules as located parse errors: malformed qualified names (`foo:`, `:foo`, `a:b:c`, `xmlns:`) are rejected; the `xmlns` prefix may never be declared; `xml` may be bound only to its own namespace name, which no other prefix (nor the default) may take, likewise the xmlns namespace name; a prefix may not be undeclared (Namespaces 1.0); attributes must be distinct by expanded name (the same URI+local name through two prefixes is a duplicate); PI targets and entity/notation names are NCNames; and a namespace declaration whose attribute is DTD-declared with a tokenized type binds its normalized value (so ` urn:x ` and `urn:x` are one namespace name, eduni ns 012). Clears all 18 namespace cases from the eduni baseline, leaving only the four #137 encoding-mismatch cases; xmltest valid/sa/012 (an attribute literally named `:`) joins the documented deviations per the suite's own NAMESPACE='no' flag, mirrored by the eduni runner's new NAMESPACE filter.
- W3C xmlconf eduni sections (#121, #127): the Edinburgh errata suites (2e, 3e, and the 5th-edition 4e), Namespaces 1.0 with its errata, and the misc cases run via the XMLCONF_ROOT runner; XML 1.1 and Namespaces 1.1 are explicitly out of scope and EDITION-gated cases skip when they do not apply to the Fifth Edition. The burn-down fixed a real spec bug and several errata behaviors: attribute values now get the 3.3.3 CDATA normalization (literal whitespace becomes a space before reference decoding, so character-referenced whitespace survives, fixing errata E36 and E20 semantics) and tokenized normalization collapses only SPACE characters; an undeclared general entity in content or an attribute value is a deferred validity finding instead of a fatal error when unread external declarations might supply it (production 68; the reference stays literal, nothing is fetched), matching the scanner-side split; the errata E15 family is enforced (any reference, comment, PI, or whitespace inside an element declared EMPTY; direct or double-escaped character-reference whitespace as character data in element content, while entity-supplied whitespace stays legal); errata E2 reports duplicate tokens in enumerated and NOTATION declarations; errata E14's declaration-completed-inside-a-PE-replacement parses and reports VC: Proper Declaration/PE Nesting; the ID family must be NCNames under namespace validation; and DTD-strict mode requires namespace declarations to be declared like any attribute. Remaining deviations are exact and classified: 24+1 grapheme-cluster lexing cases (a combining mark after an ASCII delimiter merges into one Swift Character), 18 namespace-constraint cases, 4 encoding-declaration mismatches, and E18 (per-entity base-URI tracking), each filed as its own issue.
- W3C xmlconf japanese section, fully clean (#121, #126): all 13 cases (the same prose and parameter-entity DTDs encoded as UTF-8, UTF-16 in both byte orders, Shift_JIS, EUC-JP, and ISO-2022-JP) decode through PureXML's own byte decoder, parse, and DTD-validate cleanly with zero deviations; the optional encodings the suite classifies as TYPE='error' are all supported, so they are held to the must-parse bar.
- W3C xmlconf IBM section, clean to two documented classes (#121, #125): the deepest block, 1094 cases. Valid 220/220 (parse + strict DTD validation), invalid 64/64 reporting, not-wf 529/810 rejected with the 281 accepted cases being exactly two documented classes: 279 cases from productions 85-89, the 1998 character-class appendices deleted by XML 1.0 Fifth Edition (whose count is asserted exactly so drift in either direction is caught), and 2 parameter-entity-in-internal-subset feature cases (the xmltest 160-162 class, headed for #128's strict profile). Closing the section's real gaps: a document without a root element is rejected (production 1); an entity reference in an entity literal must be a lexical Name or character reference (production 68); WFC: No Recursion is enforced at declaration over the combined general/parameter reference graph (CDATA-shielded), so a recursive pair is rejected without being referenced; an undeclared parameter-entity reference is a well-formedness error when the document is standalone or has neither an external subset nor parameter entities, and a deferred validity finding otherwise (the production-68 WFC/VC split, also applied to entity references in attribute defaults); a declared external PE the resolver refused is neither; and a content-model group opening in one PE replacement and closing in another is reported (VC: Proper Group/PE Nesting).
- Standalone validity constraints (#134): a document declaring `standalone='yes'` is now checked against its external-subset dependencies (2.9). The DTD scanner records declaration provenance (which entities, element models, and attribute lists came from the internal subset); the validator reports an externally-declared attribute default that would be supplied, an attribute value an externally-declared non-CDATA type would normalize, and whitespace inside externally-declared element content. The parser enforces the matching well-formedness side: a standalone document referencing an entity declared outside the internal subset reports it as undeclared (WFC: Entity Declared). This empties the entire Sun baseline: the section is fully clean at not-wf 56/56, valid 28/28, invalid 74/74, zero deviations, closing #124.
- DTD validity constraints, second Sun burn-down (#121, #124): the validator now enforces VC Root Element Type (the root element must match the DOCTYPE name, recorded by the scanner), VC Unique Element Type Declaration (duplicate `<!ELEMENT>` reported, first stays in effect), VC No Duplicate Types in mixed content, VC One ID per Element Type, VC Notation Attributes (listed names must be declared) and VC Notation Declared (an NDATA entity's notation must exist), VC Attribute Default Legal across the tokenized types plus VC ID Attribute Default (an ID attribute must be #IMPLIED or #REQUIRED), lexical Name checks for ID/IDREF/IDREFS values, and CDATA sections as character data in element content even when empty. Strict mode additionally requires every attribute to be declared (VC Attribute Value Type; namespace declarations exempt). Declaration-level findings are computed once when the schema is built and reported at the document root. Sun invalid coverage moves from 43/74 to 62/74 reporting; the twelve remaining silent cases are one family, the standalone='yes' VCs, which need declaration-provenance tracking.
- Entity content splicing (#133): a general entity whose replacement text contains markup, directly or through entities it references, is now reparsed as content at the point of reference (4.4.2 Included), so `<p>text</p>` inside an entity becomes a `p` element in the tree and in the pull-event stream, in both strict and recovering modes, instead of being included as escaped character data. The replacement is validated (the reference-time balanced-content WFC), checked for reference cycles, and budgeted against the amplification cap before being spliced into the reader's stream. Character references in internal entity literals now expand when the declaration is parsed for general entities too (4.4.5, previously parameter entities only), so `&#60;foo>` stores real markup that splices, and the Appendix D double escape `&#38;#38;` stores `&#38;` and renders as a literal ampersand; the reference-time WFC accordingly validates remaining references instead of re-expanding them. Text-only entities keep the single-pass expansion path and its event coalescing. Closes the last two Sun valid deviations: the section is now 28/28 valid.
- Validity-layer conformance, first Sun burn-down (#121, #124): tokenized attribute values are normalized per 3.3.3 before validity checks (whitespace runs collapse, outer whitespace strips, CDATA untouched), so ` nonce ` satisfies an enumeration and an entity-expanded IDREF resolves; an external parsed entity's leading text declaration is stripped per 4.3.1 (and validated: version optional, encoding required, standalone forbidden) instead of being included in the replacement text; character references in parameter-entity literals are expanded at declaration time per 4.4.5, making the spec's Appendix D `&#37;zz;` example parse; and a PI target inside the DTD subset must be separated from its data (production 16). Sun baselines tighten to not-wf 55/56, valid 26/28, invalid 43 reporting; the two remaining valid failures share one cause, filed separately: general-entity replacement text containing markup is included as character data rather than reparsed into elements.
- W3C xmlconf Sun section runner (#121, #124): the first validity-layer runner. Sun's manifests classify cases three ways and the runner checks all three: not-wf rejected by the strict parser (54/56), valid documents parse AND DTD-validate cleanly (19/28), invalid documents parse but must report at least one validity error (43/74). The exact deviation baselines are carried in the test with their causes: tokenized attribute-value normalization (3.3.3), external-entity text declarations (4.3.1), declaration-time character-reference expansion in PE literals (4.4.5), the standalone VCs, ID/IDREF corners, #REQUIRED enforcement, per-type attribute VCs, and the root/DOCTYPE name match, the work list this issue burns down.
- W3C xmlconf OASIS/NIST section, fully clean (#121, #123): a second opt-in runner (XMLCONF_ROOT-gated, suite never vendored) drives the oasis section from its own manifest, parsed with PureXML itself; all 247 not-wf cases are rejected and all 100 well-formed (valid + invalid) cases parse, with zero deviations (the one excluded case is flagged NAMESPACE='no' by the manifest itself: pre-namespace colons in names, which a namespace-aware parser correctly refuses). Closing the section's last 24 gaps made the DTD subset grammar strict: unknown, lowercase, or space-separated markup-declaration keywords are rejected; a parameter-entity reference must be '%' Name ';' exactly; entity, parameter-entity, and notation names must start with a NameStartChar; NDATA requires whitespace and a strict name; a notation declaration requires its identifier and a clean tail; entity value literals admit no bare '%' (production 9); conditional-section keywords are case-sensitive INCLUDE/IGNORE and sections must balance to their ']]>'; junk between declarations is not well-formed; a grammar violation in the external subset now rejects the document (previously swallowed); the external subset may open with a text declaration (version optional, encoding required, standalone forbidden, production 77); and a processing-instruction target must be separated from its data by whitespace (production 16). The new strictness also tightened the xmltest baseline from 180/186 to 181/186: a CDATA section in the internal subset (case 107) is now correctly rejected by the conditional-keyword check, leaving five documented deviations.

### Changed

- Schema-consistency checks now run through the validation framework (#117 follow-up): the derivation `final` check and Particle Valid (Restriction) are composable `Validation<SchemaTypeFact, CompiledSchemaFacts>` rules (`finalRespected`, `restrictionsAreSubsets`) applied per named type, so a schema with several problems reports them ALL at once. `SchemaError.finalViolation` and `.invalidRestriction` are replaced by `.inconsistent([String])` carrying every finding with its type's coding path; the finding texts are unchanged. `checkRedefine`, `checkAllGroups`, and `notASchema` stay fail-fast throws because they examine the raw schema source, the compilation analog of well-formedness.
- Document-order sorts no longer recompute root paths per comparison (#113): node-set ordering (the evaluator's order-and-dedup, EXSLT's set functions, string-value coercion's first-node lookup) goes through decorate-sort-undecorate helpers (`sortedByDocumentOrder()`, `firstInDocumentOrder()`) that compute each node's order key once, turning O(n log n x depth) sorts into O(n log n). `set:leading`/`set:trailing` also reuse one precomputed pivot key. Behavior is unchanged.
- XPath compilation moved out of the per-node loops (#112): XSLT template selection now resolves each match pattern once per transform through a per-run match cache (the pattern's node set is computed once over the source tree, then membership is an identity lookup), instead of recompiling and re-walking the tree for every (node, template) pair; and the XSD identity validator compiles each selector and field XPath once per run through a query cache instead of once per visited element. Schematron already stored compiled queries. Behavior is unchanged; a multi-template shape test guards the path.
- The HTML document builder's body is now constructed as a live mutable `TreeNode` tree with a single open-elements stack (the HTML5 model), attaching nodes to their parent as they open rather than accumulating children on close (#83, internal). Behavior is unchanged; this is the foundation the adoption agency algorithm needs to reparent already-built subtrees.
- DTD attribute validation is now decomposed into five named, independently composable `Validation` rules (#101): `DTD.requiredAttributes`, `fixedAttributeValues`, `enumeratedAttributeValues`, `tokenizedAttributeTypes`, and `notationAttributes`, replacing the single `attributeDeclarations` rule. Each is removable by identity and isolation-tested one constraint at a time, honoring the validation-framework idiom. Behavior is unchanged. (XSD content validation stays one recursive rule by a documented scope decision, since its constraints are interdependent through type resolution; Schematron already exposes its rules as composable `Validation<Node, Void>` values.)

### Added

- Parser strictness, first W3C-suite pass (#105 Tier 2, #120): the strict parser now rejects `--` inside comments (including the `--->` ending), a raw `<` in attribute values, the literal `]]>` sequence in character data, attributes not separated by whitespace, and characters outside the XML `Char` production in content, five new located `ParseError` cases. Driven by a new opt-in runner for the W3C XML Conformance Test Suite's xmltest section (`XMLTS_ROOT`-gated; the suite is never vendored because its license permits redistribution only as the unmodified archive): valid/sa 118/119, not-wf/sa rejection improved from 80 to 180 of 186 and valid/sa to 119/119 across five strictness passes (the second adds character-reference validation, lowercase-x-only hex references and the referenced code point must be a valid XML Char; the reserved 'xml' PI target, legal only as the declaration at the document's very first bytes; and XML Char validation in comments and PI data; the third validates <!ELEMENT> content models against the XML 1.0 grammar at DTD scan time, rejecting unbalanced parentheses, #PCDATA misplacement and nesting, mixed connectors, whitespace-detached or doubled quantifiers, empty groups, and SGML leftovers; the fourth makes the DTD declaration grammar strict: <!ENTITY> whitespace and name rules, junk after a value, NDATA spacing and its general-entities-only rule, entity-value literals checked for XML Chars and complete references, SYSTEM/PUBLIC identifiers parsed strictly with PubidChar validation, <!ATTLIST> validated against productions 52-60, the reserved xml PI target rejected inside the subset, strict UTF-8 decoding, the XML declaration's version/encoding value grammar, and required whitespace between pseudo-attributes; the fifth implements the replacement-text well-formedness constraint: when a general entity is referenced, its replacement (character references expanded as at declaration) must reparse as balanced content in isolation, so a bare or incomplete reference, a raw '<' in an embedded attribute value, tags spanning the entity boundary, and a reserved-target PI inside the replacement are rejected at the point of use, while an unreferenced entity may carry any value and only the first declaration of a name binds, both per spec; references in attribute-list defaults must name already-declared internal entities with a non-recursive chain; and a CDATA section inside replacement text now shields its content from reference expansion. The six remaining suite deviations are deliberate: internal-subset conditional/CDATA sections and parameter-entity references are supported as features, and one case expects pre-Fifth-Edition name-character classes), with the exact remaining baseline carried in the test and the two remaining leniency classes (internal-subset DTD grammar, entity replacement-text well-formedness) tracked as #120.
- XSD Particle Valid (Restriction) (#117): a complex type derived by restriction is now checked at schema compile to accept a structural subset of its base, covering element name matching, element-vs-wildcard admission, wildcard narrowing, occurrence-range subsumption, and the group recursions (sequence/all order-preserving with emptiable skips, choice mapping, sequence-into-choice, sequence-into-all, RecurseAsIfGroup). A structurally unfaithful restriction (widened occurrence, new element name, reordered sequence, content added to an EMPTY or required-into-empty base, an element outside a base wildcard's namespace) throws `SchemaError.invalidRestriction` with the type, base, and reason. The spec's effective-total-range arithmetic for MapAndSum is approximated by per-particle checks, a documented simplification.
- Conformance corpus harness (#105, Tier 2): the start of conformance-suite checking, expressed through the validation framework (the OpenAPIKit idiom). A `PureXML.Validation.ConformanceCase` is a `Validatable` named expectation (actual vs spec-authoritative expected output), and `Conformance.matchesExpected` is a `Validation<ConformanceCase, Void>` rule that emits one located `ValidationError` per diverging case, so a whole suite reports every failure at once with the case name as its coding path. Seeded with a Canonical XML 1.0 corpus (attribute ordering, empty-element expansion, comment removal, CDATA-to-escaped-text, processing instructions, namespace rendering) an XPath 1.0 core-function corpus, and an XSD datatype/facet corpus (length, range, pattern, enumeration, lexical space), a RELAX NG pattern corpus (text, optional, repetition, choice, ordered group, attribute, interleave, empty), an XSLT 1.0 transformation corpus (value-of, for-each, if, choose, sort, variable, format-number, apply-templates, call-template), an HTML5 tree-construction corpus (void elements, implied tag closing, case normalization, the adoption agency, entities), a Schematron corpus (assert, report, rule context), a C14N exclusive/2.0 corpus (unused-namespace dropping, render-at-use, whitespace trimming), an XPath axes/predicates corpus (descendant, ancestor, sibling axes, positional and attribute predicates, union), a DTD content-model corpus (sequence, choice, occurrence indicators, mixed, EMPTY, ANY), an XInclude/XPointer corpus (substitution, text inclusion with escaping, fallback, relative href resolution; shorthand ids, element() navigation, xpointer() including the per-step predicate semantic), an XSD regex corpus (implicit whole-string anchoring, the character-class escapes, Unicode categories, quantifier ranges, alternation, class negation and subtraction), and an XML Catalog corpus (system/public/uri entries, rewrite prefixes, unmatched identifiers). The HTML corpus surfaced its first divergence (the fragment parser does not reconstruct active formatting elements like the document parser, tracked as #109). Growing the corpora against the official W3C/OASIS suites is the ongoing Tier-2 work.
- EXSLT extension functions (#105, Tier 3): the `common`, `math`, and `sets` EXSLT modules, dispatched by resolving a function's prefix to its namespace (so any prefix bound to an EXSLT namespace works). `math:min`, `math:max`, `math:highest`, `math:lowest`, `math:abs`, `math:sqrt` (with the EXSLT NaN rule for non-numeric nodes); `set:distinct`, `set:difference`, `set:intersection`, `set:has-same-node`, `set:leading`, `set:trailing` (by node identity and document order); `exsl:object-type`. `math:power` and the other transcendentals are omitted because they need a C math library, which the pure-Swift, Foundation-free target excludes; `exsl:node-set` awaits result-tree-fragment support.
- Canonical XML 1.1 (#105, Tier 3): a `Canonical.Options.canonical11` preset and a `mergeInheritedBase` option. When canonicalizing a document subset, the `xml:base` values of the apex's omitted ancestors are merged into the apex by RFC 3986 reference resolution (vs. 1.0's nearest-ancestor rule), the apex's own relative `xml:base` is resolved against that chain, and `xml:id` is no longer inherited; `xml:lang` and `xml:space` still inherit the nearest. A self-contained RFC 3986 resolver (scheme/authority/path parsing, path merging, dot-segment removal) backs the merge.
- Single-byte legacy encodings (#97): the byte decoder gains a table-based single-byte path and the full set of single-byte legacy encodings, selected by the XML declaration's `encoding` name for both the whole-buffer and streaming decoders: the complete ISO-8859 family (parts 2 through 16), Windows-1250/1251/1253/1254/1255/1256/1257/1258, and KOI8-R/U. Most are vendored verbatim from the authoritative `unicode.org` mapping files; ISO-8859-5/9/15 are derived exactly; Windows-1254 composes from Windows-1252. Multi-byte CJK encodings (#99) are tracked separately.

### Fixed

- XSD identity-constraint XPath compile errors are no longer swallowed (#111): a selector or field XPath that fails to compile is reported once up front as a located error ("identity constraint 'k': invalid field XPath '...'"), instead of `try?` silently turning a schema author's typo into a disabled constraint. The broken query still evaluates as no-match afterwards, so the rest of the document is validated.
- XSD type resolution no longer accepts invalid input silently (#110): an `xsi:type` naming an undeclared type is now a located error ("unknown xsi:type '...'") instead of a silent fallback to the declared type, in both the tree and streaming validators; and `typeReference` chains are resolved through one shared cycle-detecting resolver, so a circular chain reports "circular type reference '...'" instead of silently truncating after 64 hops (and no longer recurses without bound in the streaming shallow check, a latent crash). Completions use the same resolver, best-effort.
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
