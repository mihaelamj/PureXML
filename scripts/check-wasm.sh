#!/usr/bin/env bash

set -euo pipefail

SDK_ID="${SWIFT_WASM_SDK_ID:-swift-6.3.2-RELEASE_wasm}"
SWIFT_SELECTOR="${SWIFT_WASM_SWIFT_SELECTOR:-+6.3.2}"

swift_command() {
  if command -v swiftly >/dev/null 2>&1; then
    swiftly run swift "$@" "$SWIFT_SELECTOR"
  else
    swift "$@"
  fi
}

if ! swift_command sdk list | grep -qx "$SDK_ID"; then
  echo "wasm: missing Swift SDK '$SDK_ID'" >&2
  echo "wasm: install the SDK or set SWIFT_WASM_SDK_ID" >&2
  exit 2
fi

swift_command build --swift-sdk "$SDK_ID"
swift_command build -c release --swift-sdk "$SDK_ID"

# Runtime proof (#144): when wasmtime is available, the full test suite
# executes on an actual WASI runtime; the first such run caught a real
# wasm32 trap (32-bit Int conversion in format-number). Build-only when
# wasmtime is absent, with a notice.
if command -v wasmtime >/dev/null 2>&1; then
  swift_command build --build-tests --swift-sdk "$SDK_ID"
  TEST_BINARY="$(ls .build/wasm32-*/debug/*PackageTests.xctest 2>/dev/null | head -1)"
  if [ -n "$TEST_BINARY" ]; then
    wasmtime run --dir . "$TEST_BINARY" --testing-library swift-testing
  else
    echo "wasm: test binary not found; skipping runtime execution" >&2
  fi
else
  echo "wasm: wasmtime not installed; build-only (install wasmtime for the runtime proof)" >&2
fi
