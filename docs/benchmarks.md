# Benchmarks: PureXML vs libxml2 (#139)

`bash scripts/benchmark.sh [items] [iterations]` generates a deterministic
corpus (never vendored), builds PureXML in release and the C driver against
the macOS SDK's libxml2, runs both over the same bytes with internal timing
(best-of-N, IO excluded), and prints the comparison. Both drivers also
cross-check the same XPath count, so every benchmark run doubles as a
cross-implementation correctness check.

## Baseline (first measurement)

20000 items, ~4.2 MB, best of 5, Apple Silicon (Studio), release builds:

| operation | PureXML | libxml2 | ratio |
|---|---|---|---|
| parse | 0.49 s | 0.016 s | ~30x |
| serialize | 0.059 s | 0.012 s | ~5x |
| xpath | 0.42 s | 0.012 s | ~36x |

These are the honest starting numbers the #139 optimization passes burn
down; the table updates as passes land, never silently.

## Current record (size series + real corpora, best of 3)

| corpus | parse | serialize | xpath |
|---|---|---|---|
| generated 4.2 MB | 0.34 s (18.7x) | 0.064 s (5.5x) | 0.15 s (11.9x) |
| generated 42 MB | 3.49 s (18.7x) | 0.63 s (5.6x) | 1.57 s (11.7x) |
| generated 210 MB | 19.3 s (19.7x) | 3.19 s (5.6x) | 9.4 s (libxml2: **refused**) |
| NASA ADC 25 MB (real) | 1.73 s (24.5x) | 0.42 s (8.0x) | 0.76 s (19.4x) |
| SwissProt 115 MB (real) | 11.0 s (22.0x) | 1.77 s (5.5x) | 5.0 s (18.7x) |

Two findings only the large corpora could surface:

- PureXML's document-order sort was quadratic on flat fan-outs (42 MB:
  27 s in XPath, ratio 190x). Fixed; and the first fix attempt was itself
  quadratic in a worse place (an eager sibling-table built per predicate
  evaluation: one hour at 42 MB), caught by sampling the live run. The
  cache now early-outs single-node sets and builds a parent's table only
  on its second lookup. XPath at 42 MB: 27.1 s -> 1.57 s.
- libxml2 refuses XPath evaluation past its XPATH_MAX_NODESET_LENGTH cap
  (10M nodes): the 210 MB corpus query returns NULL by design. PureXML
  completes it in 9.4 s. The protective counterpart for hostile input is
  tracked as #143.

Scaling: all three PureXML operations are linear in document size (ratios
flat from 4 MB to 210 MB), and there is no 2 GB integer cliff (64-bit
offsets throughout; libxml2's xmlReadMemory takes an int byte count).

## Optimization log

| pass | change | parse | xpath | serialize |
|---|---|---|---|---|
| baseline | - | 0.494 s (30x) | 0.413 s (37x) | 0.061 s (5.5x) |
| 1 | allocation-free Reader.matches() | 0.414 s (26x) | unchanged | unchanged |
| 2 | byte-backed Reader (owned UTF-8 storage, pointer-decoded scalars, byte-level literal match/consume) | 0.375 s (23x) | unchanged | unchanged |
| 3 | bulk content runs (plain-ASCII character data scanned and consumed at the byte level, String built once per run) | 0.335 s (20x) | unchanged | unchanged |
| 4 | byte-level dispatch + name/attribute scanning (non-buffering `peekByte`, byte-mode `skipSpace`, all-ASCII `takeASCIIName`, `attributeRunBytes`); keeps the lookahead buffer empty so the existing byte fast paths engage | 0.217 s (13x) | unchanged | unchanged |
| 5 | `sawAmpersand` short-circuit (ampersand-free text returns verbatim, skipping the reference-decode/split/findings pass) and detecting the text-run-closing `<` via `peekByte` instead of buffering it (the buffered `<` had cascaded the next element's whole dispatch and name scan onto the Character path) | 0.157 s (9.5x) | unchanged | unchanged |
| 6 | byte-level markup dispatch (the single byte after `<` selects end-tag/PI/declaration/start-tag, replacing up to five literal string comparisons per element with one byte peek) | 0.147 s (9.0x) | unchanged | unchanged |
| 7 | `sawAmpersand` short-circuit for attribute values (the byte scanner notes any `&`; an ampersand-free value skips the reference-decode pass and its full re-scan); measured against same-state baseline, every run below every baseline run | 0.143 s (~4% vs baseline) | unchanged | unchanged |
| 8 | serialize escaping fast path (text/attribute/comment/PI return the value unchanged when no character needs escaping, instead of rebuilding it character by character; byte-level scan for the escapable bytes) | unchanged | unchanged | 0.032 s (2.7x, from 5.5x) |
| 9 | skip cross-context node-set de-duplication on a single context or a disjoint axis (child/attribute/namespace/self); the `Set<Node>` hashing and copying was pure overhead where no duplicate can arise, same output (same-state A/B, ~28%) | unchanged | 0.097 s (10x, from 13x) | unchanged |
| 10 | `//` descendant fusion (`descendant-or-self::node()/child::X[P]` compiled to `descendant::X[P]` when `P` is non-positional), avoiding the whole-subtree intermediate context; guarded so positional predicates keep their per-parent meaning, adversarially reviewed for semantic transparency | unchanged | 0.063 s (~7x, from 10x) | unchanged |
| 11 | drop the redundant `Set` de-duplication when sorting a path result: `evaluateSteps` already yields a duplicate-free node-set, so only the document-order sort is needed (each skipped insert was a copy of a node wrapping a side-table-refcounted tree node); same-state A/B, ~9% | unchanged | 0.058 s (~6x, from ~7x) | unchanged |
| 12 | skip the document-order sort for a single forward-axis step from one context: `AxisNavigation` produces child/descendant/descendant-or-self/self/following/following-sibling already in document order with no duplicates, so the sort is redundant (adversarially reviewed for order correctness; same-state A/B, ~7%) | unchanged | 0.055 s (~6x) | unchanged |
| 13 | single-accumulator descendant traversal: `descendants(of:)` recursed on wrapped nodes and concatenated a fresh array at every node (`append(contentsOf: descendants(of: child))`), O(n x depth) allocation churn; rewritten to recurse on the raw tree node with one shared `inout` accumulator, O(n). Same output (same-state A/B, ~46%) | unchanged | 0.032 s (~3x, from ~6x) | unchanged |
| 14 | fuse the node test into the descendant walk: a node the step's test rejects is no longer wrapped in an `XPath.Node` (so never retained); `matches` delegates to a tree-node `matchesTree` so there is one source of truth, and the traversal applies it during the walk. Identical node-set (adversarially equivalence-reviewed; same-state A/B, ~11%) | unchanged | 0.028 s (~2.5x) | unchanged |
| 15 | the same test fusion for the attribute axis (`matchesAttribute`): a `[@name='...']` predicate built every attribute node per element and filtered to one; it now wraps only the matching attribute, saving the owner retain and the qualified-name/value copies for the rest. Identical node-set (adversarially equivalence-reviewed; same-state A/B, ~20%) | unchanged | 0.022 s (~2.0x) | unchanged |
| 16 | share the focus-independent evaluation state via an `Environment` reference: `focused(on:position:size:)` (called once per node of a predicate's input) copied the variables, functions, and namespace dictionaries every time; it now copies only node/position/size and shares one reference. Same semantics (same-state A/B, ~16%) | unchanged | 0.020 s (~2.0x) | unchanged |
| 17 | compile the step's node test once per query instead of re-evaluating it per node: the descendant/attribute walks called `{ matchesTree($0, step.test, on: step.axis, context.namespaces) }`, passing the `namespaces` dictionary (and the `NodeTest`'s associated string) by value on every one of tens of thousands of nodes, so the dominant traversal carried a dictionary retain/release per node. `compiledTreeTest`/`compiledAttributeTest`/`compiledNodeTest` resolve the axis principal kind, the binding state, and the name shape once and return a tight closure capturing only the local name. Equivalent to `matchesTree`/`matchesAttribute`/`matches` (exhaustive differential test + adversarial review; same-state A/B, ~35%) | unchanged | 0.013 s (~1.3x) | unchanged |
| 18 | bulk-copy literal runs in the entity decoder: `EntityExpander.expand` rebuilt every reference-bearing text run one character at a time (`result.append(character)` with a per-character budget charge), so a text node holding a single `&amp;` was copied grapheme by grapheme; it now scans to the next `&`/`<` and appends the literal run in one go (charging the budget by the run length). Also skips the element-content reference-findings pass (an `&` scan plus a qualified-name render per text node) when there is no DTD. Identical decoded text (W3C XML conformance corpora + 6-case differential + adversarial review; same-state A/B, ~5%) | 0.138 s (~8.5x) | unchanged | unchanged |
| 19 | carry the name's first-colon offset out of the byte scanner so `QualifiedName` splits the prefix without a second pass: `takeASCIIName` already visits every name byte, so it records the first `:` (one compare per byte); `QualifiedName(ascii:colonOffset:)` then splits at the known offset, and the common unprefixed name (no colon) takes no scan at all instead of a grapheme-by-grapheme `firstIndex(of:)` over the whole name. Identical names (colon-placement differential + W3C conformance + adversarial review; same-state A/B, ~12%) | 0.124 s (~7.7x) | unchanged | unchanged |
| 20 | adopt prepared children when materializing the tree instead of appending them one at a time: building the mutable `TreeNode` tree from the parsed value `Node` ran `append` per child, which detaches the child from any old parent, checks for a cycle, and grows the children array element by element; the converted children are freshly built and parentless, so `TreeNode.init(adopting:)` takes the prepared array directly and only wires each child's parent. Identical tree (parent-wiring differential + W3C conformance + adversarial review; same-state A/B, ~12%) | 0.106 s (~6.5x) | unchanged | unchanged |
| 21 | scan for the entity decoder's markers at the byte level: `EntityExpander.expand` found the next `&`, `<`, and `;` with `String.firstIndex` over graphemes; since all three are ASCII, a UTF-8 index is a valid string index, so the scan runs over `raw.utf8` and skips decoding every literal byte into a grapheme just to look for a marker. Same decoded text (the bulk + 4 multibyte-boundary cases in the decode differential + W3C conformance; same-state A/B, ~5.5%) | 0.099 s (~6.1x) | unchanged | unchanged |
| 22 | build the mutable `TreeNode` tree directly from the event stream instead of building the value `Node` tree and converting it: `parseTree` ran `TreeNode(parse(...))`, allocating two full trees (the value tree, then a converted reference tree). `Parser.buildTree` is the direct counterpart to `build` (same event loop, stack discipline, and well-formedness guards) that accumulates `TreeNode` children per frame and adopts them when an element closes, so the tree is allocated once. Identical tree (structural differential against the convert path + the whole suite and conformance corpora, which all run through `parseTree`, + adversarial review; same-state A/B, ~8%) | 0.090 s (~5.5x) | unchanged | unchanged |

## Profile findings (first sample, parse path)

Top of stack, release build: String.Iterator.next (the per-character pull
closure chain), _stringCompareWithSmolCheck (Character equality in
matches/peek), String._uncheckedFromUTF8 and _allASCII (small-string
materialization), bridgeObjectRelease/swift_release (ARC on Character
buffers), UnicodeScalarView.distance. The Reader's architecture: one
closure call per scalar, [Character] lookahead, Character-typed
classification. The structural fix is a byte-level (UTF-8) scanner with
scalar classification tables; that is its own #139 pass, designed, not
patched.

## Known structure of the gap

- Parse and XPath dominate; serialize is closest.
- The scanner-vs-tree split needs the SAX stage, blocked on #142 (the
  public streaming surface is internal today).
- Suspects to profile, in order: Character/grapheme-based scanning versus
  byte scanning, per-scalar reader buffering (#135), ARC traffic in tree
  construction, XPath node-set materialization on every axis step.

## Rules

- Optimize only what these numbers indict, one suspect per pass, with the
  before/after recorded here.
- The corpus generator changes only with a note here, since ratios are
  only comparable over identical corpora.
