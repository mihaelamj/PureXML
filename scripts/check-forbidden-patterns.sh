#!/usr/bin/env bash
# Repo contract gate for PureXML "never" rules.
#
# These checks cover patterns that Swift unit tests cannot see reliably:
# package dependencies, source imports, C/generated parser files, XCTest-style
# tests, platform branches, and singleton/service-locator wiring.

set -u

FAIL=0

fail() {
  echo "forbidden-patterns: $1" >&2
  FAIL=1
}

report_matches() {
  message="$1"
  matches="$2"
  if [ -n "$matches" ]; then
    fail "$message"
    printf '%s\n' "$matches" | sed 's/^/  /' >&2
  fi
}

if ! grep -qE '^[[:space:]]*dependencies:[[:space:]]*\[[[:space:]]*\],[[:space:]]*$' Package.swift; then
  fail "Package.swift must keep dependencies: []"
fi

package_forbidden=$(
  grep -nE '\.package[[:space:]]*\(|\.binaryTarget[[:space:]]*\(|\.systemLibrary[[:space:]]*\(' Package.swift 2>/dev/null || true
)
report_matches "Package.swift must not declare external, binary, or system-library targets" "$package_forbidden"

source_imports=$(
  grep -RInE '^[[:space:]]*import[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' Sources --include '*.swift' 2>/dev/null || true
)
report_matches "Sources must stay standard-library-only and import no modules" "$source_imports"

source_platform_branches=$(
  grep -RInE '^[[:space:]]*#if[[:space:]]+(os|canImport)[[:space:]]*\(' Sources --include '*.swift' 2>/dev/null || true
)
report_matches "Sources must not add platform-specific branches without an explicit rule change" "$source_platform_branches"

source_runtimes=$(
  find Sources -type f \( \
    -name '*.c' -o \
    -name '*.cc' -o \
    -name '*.cpp' -o \
    -name '*.h' -o \
    -name '*.hpp' -o \
    -name '*.m' -o \
    -name '*.mm' -o \
    -name '*.js' -o \
    -name '*.ts' -o \
    -name '*.wasm' -o \
    -name '*.y' -o \
    -name '*.l' -o \
    -name '*.g4' \
  \) -print 2>/dev/null
)
report_matches "Sources must not contain C, JavaScript, WebAssembly blobs, or generated parser runtime files" "$source_runtimes"

source_singletons=$(
  grep -RInE 'static[[:space:]]+(let|var)[[:space:]]+shared\b|^[[:space:]]*(public[[:space:]]+)?(final[[:space:]]+)?(class|struct|enum)[[:space:]]+ServiceLocator\b|[A-Za-z0-9_]*(Resolver|Container|Environment)[[:space:]]*\.[[:space:]]*shared\b' Sources --include '*.swift' 2>/dev/null || true
)
report_matches "Sources must not introduce singleton or service-locator access patterns" "$source_singletons"

source_traps=$(
  grep -RInE '\bfatalError[[:space:]]*\(|\bpreconditionFailure[[:space:]]*\(|\bassertionFailure[[:space:]]*\(|\btry!|\bas!|[A-Za-z0-9_)\]}][[:space:]]*![[:space:]]*([).,\];:]|$)' Sources --include '*.swift' 2>/dev/null || true
)
report_matches "Sources must not use traps, forced casts, try!, or force unwraps" "$source_traps"

test_imports=$(
  grep -RInE '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' Tests --include '*.swift' 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*@testable[[:space:]]+import[[:space:]]+PureXML[[:space:]]*$' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*import[[:space:]]+Foundation[[:space:]]*$' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*import[[:space:]]+Testing[[:space:]]*$' || true
)
report_matches "Tests may import only Foundation, Testing, and @testable PureXML" "$test_imports"

test_xctest=$(
  grep -RInE '\bXCTest(Case|Expectation)?\b|\bXCTAssert[A-Za-z]*\b|^[[:space:]]*import[[:space:]]+XCTest[[:space:]]*$' Tests --include '*.swift' 2>/dev/null || true
)
report_matches "Tests must stay on Swift Testing and avoid XCTest-style APIs" "$test_xctest"

if [ "$FAIL" -eq 0 ]; then
  echo "forbidden-patterns: OK"
fi

exit "$FAIL"
