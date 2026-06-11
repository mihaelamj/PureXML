#!/usr/bin/env bash
# PureXML vs libxml2 benchmark (#139). Generates deterministic corpora,
# builds both drivers (PureXML in release, the C driver against the SDK's
# libxml2), runs them over the same files, and prints comparison tables.
# Nothing is vendored; corpora are regenerated on each run.
#
# Usage: bash scripts/benchmark.sh ["items items ..."] [iterations]
#        CORPUS=/path/to/file.xml bash scripts/benchmark.sh "" [iterations]
#
# The default size series spans ~4 MB, ~42 MB, and ~210 MB; pass a single
# item count to pin one size, or CORPUS to measure a real-world document.

set -euo pipefail
cd "$(dirname "$0")/.."

SIZES="${1:-20000 200000 1000000}"
ITERATIONS="${2:-3}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

generate_corpus() {
  python3 - "$1" > "$2" << 'CORPUSEOF'
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
CORPUSEOF
}

echo "==> building PureXML (release)"
swift build -c release > /dev/null
MODULES=".build/release/Modules"
[ -d "$MODULES" ] || MODULES=".build/release"
swiftc -O -I "$MODULES" Benchmarks/bench-purexml.swift .build/release/PureXML.build/*.o -o "$WORK/bench-purexml" 2> /dev/null \
  || swiftc -O -I "$MODULES" Benchmarks/bench-purexml.swift -L .build/release -lPureXML -o "$WORK/bench-purexml"

echo "==> building libxml2 driver"
SDK="$(xcrun --show-sdk-path)"
clang -O2 -I "$SDK/usr/include/libxml2" -lxml2 Benchmarks/bench-libxml2.c -o "$WORK/bench-libxml2"

run_one() {
  local file="$1" label="$2"
  echo ""
  echo "==> $label ($(wc -c < "$file" | tr -d ' ') bytes, best of $ITERATIONS)"
  "$WORK/bench-purexml" "$file" "$ITERATIONS" > "$WORK/pure.csv"
  "$WORK/bench-libxml2" "$file" "$ITERATIONS" > "$WORK/lib.csv"
  python3 - "$WORK/pure.csv" "$WORK/lib.csv" << 'TABLEEOF'
import sys
def load(path):
    rows = {}
    for line in open(path):
        library, operation, size, seconds = line.strip().split(",")
        rows[operation] = None if seconds == "refused" else float(seconds)
    return rows
pure = load(sys.argv[1])
lib = load(sys.argv[2])
print(f"{'operation':<12} {'PureXML':>12} {'libxml2':>12} {'ratio':>8}")
for operation in ["parse", "serialize", "xpath"]:
    p, l = pure.get(operation), lib.get(operation)
    if p is None or l is None:
        left = f"{p:.4f}s" if p is not None else "refused"
        right = f"{l:.4f}s" if l is not None else "refused"
        print(f"{operation:<12} {left:>12} {right:>12} {'-':>8}")
    else:
        print(f"{operation:<12} {p:>11.4f}s {l:>11.4f}s {p / l:>7.2f}x")
TABLEEOF
}

if [ -n "${CORPUS:-}" ]; then
  run_one "$CORPUS" "real corpus: $CORPUS"
else
  for items in $SIZES; do
    generate_corpus "$items" "$WORK/corpus-$items.xml"
    run_one "$WORK/corpus-$items.xml" "generated, $items items"
  done
fi
