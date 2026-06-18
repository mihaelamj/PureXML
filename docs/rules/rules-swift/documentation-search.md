# Apple Documentation: Consult cupertino, Do Not Recall

**Status: MANDATORY.** Any fact about an Apple-platform API (availability, a signature, a deprecation, a conformance, an inheritance relationship, default behavior) comes from the documentation, never from memory. An LLM's recall of Apple APIs is stale at its training cutoff and reliably invents signatures, availability floors, and conformances. Before you state such a fact, look it up. The tool for that is [cupertino](https://github.com/mihaelamj/cupertino) (`brew install mihaelamj/tap/cupertino`), a local index over current Apple documentation, available as a CLI and an MCP server.

## What cupertino is, and is not

cupertino is a **SQLite FTS5 keyword index** over Apple's documentation, ranked by field-weighted BM25, with a structured store layered on top (AST-extracted symbols with their `kind`/signature/`is_async`/`is_throws`, per-platform availability floors, a class-inheritance graph, and generic constraints pulled from the Apple SDK symbol graphs). It covers the developer docs, the Human Interface Guidelines, the Apple archive (Core Animation, Quartz 2D, KVO/KVC), Swift Evolution, Swift.org, The Swift Programming Language, and Apple sample code.

It is **not intelligent.** It does not reason, summarize, design, compare options, or answer a question. A query returns a deterministic, ranked list of document and symbol hits; the hit is a pointer, and the document it points to is the fact. The intelligence is yours; cupertino only retrieves.

## How to use it (query, then read)

1. **Query with keywords or symbol names, not a sentence.** A few terms (a symbol, a framework, a concept word) such as `NavigationSplitView`, `URLSession data delegate`, `Observable macro availability`. The text is matched, not understood, and only the first handful of terms are honored; a prose question wastes terms and returns noise.
2. **For an exact API fact, use the typed query** rather than full-text: a symbol search for a signature or whether it is `async`/`throws`; a conformance search for "does this type conform to that protocol"; an inheritance walk for the class tree; the availability filters or the document read for the deployment floors. These query the structured columns, not prose.
3. **Read the winning hit and quote it.** The ranking locates the document; reading it gives the authoritative text. Narrow by source when you know it: current API docs for current APIs, the Human Interface Guidelines for interface guidance, sample code for working examples, the archive for foundational or legacy topics, Swift Evolution for language history.

## DO

- Look up every Apple-API fact (availability, signature, deprecation, conformance, inheritance) in cupertino before stating it.
- Send keywords and symbol/framework names; prefer the typed symbol, conformance, and inheritance queries for exact facts.
- Read the returned document and cite what you read.
- Narrow by source and framework when you know them.

## DON'T

- Do not recall an Apple-API fact from memory when the documentation can settle it.
- Do not phrase a natural-language question and expect an answer; cupertino returns rows, not reasoning.
- Do not trust a rank as a fact without reading the hit; BM25 is relevance ordering, not a truth claim.
- Do not ask it to compare, weigh trade-offs, or design. That is a category error; it retrieves, you reason.

## Acceptance check

Before any Apple-API fact appears in code, a comment, or a claim, it was looked up in cupertino (a keyword or typed query, then the returned document read), not recalled from memory. A signature, an availability floor, or a conformance asserted from memory without a lookup fails this rule, even if it happens to be right.

## Why it beats memory

cupertino is the actual Apple documentation, crawled and indexed, plus the Apple SDK symbol graphs, kept current. It is deterministic (the same query always returns the same hits) and local (sub-second). An LLM's training-cutoff recall is the opposite on every axis: stale, non-deterministic, and prone to inventing the exact facts (availability, signatures, deprecations) that break a build or ship a bug.

## Companion rules

- `core/no-shortcuts-first-principles.md`: reason from the source, not from memory; a guessed API fact is a shortcut.
- `core/first-principles-analysis.md`: check every checkable fact against the source.
- `framework-policy.md`: the Apple-platform discipline these facts serve.
