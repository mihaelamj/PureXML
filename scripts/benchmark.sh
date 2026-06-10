#!/usr/bin/env bash
# PureXML vs libxml2 benchmark (#139). Generates a deterministic corpus,
# builds both drivers (PureXML in release, the C driver against the SDK's
# libxml2), runs them over the same file, and prints a comparison table.
# Nothing is vendored; the corpus is regenerated on each run.
#
# Usage: bash scripts/benchmark.sh [items] [iterations]

set -euo pipefail
cd "$(dirname "$0")/.."

ITEMS="${1:-20000}"
ITERATIONS="${2:-5}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Deterministic corpus: nested records with attributes, text, and namespaces.
python3 - "$ITEMS" > "$WORK/corpus.xml" << 'PYEOF'
import sys
items = int(sys.argv[1])
out = sys.stdout
out.write('<?xml version="1.0" encoding="UTF-8"?>\n')
out.write('<catalog xmlns:m="urn:meta">\n')
for i in range(items):
    kind = "even" if i % 2 == 0 else "odd"
    out.write(f'  <item id="i{i}" kind="{kind}" m:rank="{i % 97}">\n')
    out.write(f'    <name>Item number {i} &amp; friends</name>\n')
    out.write(f'    <price currency="EUR">{(i * 37) % 1000}.{i % 100:02d}</price>\n')
    out.write(f'    <note xml:space="preserve">line one\nline two for {i}</note>\n')
    out.write('  </item>\n')
out.write('</catalog>\n')
PYEOF
SIZE=$(wc -c < "$WORK/corpus.xml" | tr -d ' ')
echo "corpus: $ITEMS items, $SIZE bytes, best of $ITERATIONS runs"

echo "==> building PureXML (release)"
swift build -c release > /dev/null
MODULES=".build/release/Modules"
[ -d "$MODULES" ] || MODULES=".build/release"
swiftc -O -I "$MODULES" Benchmarks/bench-purexml.swift .build/release/PureXML.build/*.o -o "$WORK/bench-purexml" 2> /dev/null \
  || swiftc -O -I "$MODULES" Benchmarks/bench-purexml.swift -L .build/release -lPureXML -o "$WORK/bench-purexml"

echo "==> building libxml2 driver"
SDK="$(xcrun --show-sdk-path)"
clang -O2 -I "$SDK/usr/include/libxml2" -lxml2 Benchmarks/bench-libxml2.c -o "$WORK/bench-libxml2"

echo "==> running"
"$WORK/bench-purexml" "$WORK/corpus.xml" "$ITERATIONS" > "$WORK/pure.csv"
"$WORK/bench-libxml2" "$WORK/corpus.xml" "$ITERATIONS" > "$WORK/lib.csv"

python3 - "$WORK/pure.csv" "$WORK/lib.csv" << 'PYEOF'
import sys
def load(path):
    rows = {}
    for line in open(path):
        library, operation, size, seconds = line.strip().split(",")
        rows[operation] = float(seconds)
    return rows
pure = load(sys.argv[1])
lib = load(sys.argv[2])
print(f"{'operation':<12} {'PureXML':>12} {'libxml2':>12} {'ratio':>8}")
for operation in ["parse", "serialize", "xpath"]:
    p, l = pure[operation], lib[operation]
    print(f"{operation:<12} {p:>11.4f}s {l:>11.4f}s {p / l:>7.2f}x")
PYEOF
