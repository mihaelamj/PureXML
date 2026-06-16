#!/usr/bin/env bash
# Full local verification gate for PureXML.
#
# Runs the checks required before completion. The Linux and WASM gates are
# available as separate scripts (scripts/check-linux.sh, scripts/check-wasm.sh)
# and run in hosted CI; they are not chained here so this gate stays runnable on
# any machine without remote infrastructure or a Wasm SDK.

set -euo pipefail

run_gate() {
  name="$1"
  shift
  printf '\n==> %s\n' "$name"
  "$@"
}

run_gate "style" bash scripts/check-style.sh
run_gate "namespacing" bash scripts/check-namespacing.sh
run_gate "forbidden patterns" bash scripts/check-forbidden-patterns.sh
run_gate "validation coverage" bash scripts/check-validation-coverage.sh
run_gate "validation field coverage" bash scripts/check-validation-fields.sh
run_gate "changelog" bash scripts/check-changelog-touched.sh
run_gate "swiftformat" swiftformat . --config .swiftformat --lint
run_gate "swiftlint" swiftlint --config .swiftlint.yml --strict
run_gate "swift build" swift build
run_gate "swift test" swift test
