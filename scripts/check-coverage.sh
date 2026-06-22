#!/usr/bin/env bash
# Line-coverage report and gate for the standing test suite.
#
# A code-coverage pass (not enforced before) found two source files at 0% line
# coverage in the plain `swift test` run -- exercised only by the opt-in XSTS/XSLT
# gates, so a normal run never touched them. This script makes that measurable: it
# runs the instrumented suite, prints overall coverage and the lowest-covered
# files, and FAILS if any source file sits at 0% line coverage (a clear signal of
# untested or dead code).
#
# It is opt-in (not chained into check-all.sh) because the instrumented build and
# llvm-cov are slow and macOS-only (xcrun llvm-cov). Run it when adding a source
# file or before a release: `bash scripts/check-coverage.sh`.
#
# An optional region floor can be set: COVERAGE_REGION_FLOOR=80 fails the run when
# overall region coverage drops below 80%.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "coverage: xcrun/llvm-cov unavailable (macOS only); skipping." >&2
  exit 0
fi

echo "==> swift test --enable-code-coverage"
swift test --enable-code-coverage >/dev/null 2>&1 || { echo "coverage: test run failed" >&2; exit 1; }

prof="$(find .build -path '*/debug/codecov/default.profdata' 2>/dev/null | head -1)"
if [ -z "$prof" ]; then
  echo "coverage: could not locate profdata" >&2
  exit 1
fi
# The instrumented binary lives in the same (debug) build dir as the profdata; a
# release .xctest may also exist but carries no coverage data, so derive the path
# rather than search (which could pick the wrong one).
debugdir="$(dirname "$(dirname "$prof")")"
bin="$(find "$debugdir" -path '*PureXMLPackageTests.xctest/Contents/MacOS/*' -type f 2>/dev/null | head -1)"
if [ -z "$bin" ]; then
  echo "coverage: could not locate the debug test binary under $debugdir" >&2
  exit 1
fi

json="$(mktemp)"
trap 'rm -f "$json"' EXIT
xcrun llvm-cov export "$bin" -instr-profile="$prof" \
  -ignore-filename-regex='(Tests|\.build|checkouts)/' >"$json" 2>/dev/null

FLOOR="${COVERAGE_REGION_FLOOR:-0}" python3 - "$json" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))["data"][0]
files = [f for f in data["files"] if "/Sources/" in f["filename"]]
tot = data["totals"]
line = tot["lines"]["percent"]
region = tot["regions"]["percent"]
func = tot["functions"]["percent"]
print(f"overall: lines {line:.2f}%  regions {region:.2f}%  functions {func:.2f}%  ({len(files)} source files)")

def short(fn): return fn.split("/Sources/", 1)[1]
ranked = sorted(files, key=lambda f: f["summary"]["lines"]["percent"])
print("lowest-covered source files:")
for f in ranked[:8]:
    s = f["summary"]["lines"]
    print(f"  {s['percent']:6.1f}%  {s['count']-s['covered']:4d} missed  {short(f['filename'])}")

zero = [short(f["filename"]) for f in files if f["summary"]["lines"]["percent"] == 0 and f["summary"]["lines"]["count"] > 0]
floor = float(os.environ.get("FLOOR", "0"))
fail = False
if zero:
    print("\nFAIL: source files with 0% line coverage (untested or dead code):", file=sys.stderr)
    for z in zero:
        print(f"  {z}", file=sys.stderr)
    fail = True
if floor > 0 and region < floor:
    print(f"\nFAIL: overall region coverage {region:.2f}% is below floor {floor:.0f}%", file=sys.stderr)
    fail = True
if not fail:
    print("\ncoverage: OK")
sys.exit(1 if fail else 0)
PY
