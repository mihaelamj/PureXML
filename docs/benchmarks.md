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
