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
