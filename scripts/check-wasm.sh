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
