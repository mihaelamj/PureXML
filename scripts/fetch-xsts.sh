#!/usr/bin/env bash
# Fetch the W3C XML Schema Test Suite (XSTS, 2006-11-06 release) to the path the
# conformance runner (Tests/XSTSSuiteTests.swift) expects.
#
# The extracted suite is never vendored: the W3C Document License permits
# redistribution only as the complete unmodified archive, and the corpus is about
# 200 MB across 39,399 files. The unmodified archive itself is vendored at
# Tests/Fixtures/xsts; this script extracts that when present (no network), or
# downloads the official archive otherwise, verifying its SHA-256 before extracting.
#
# Usage:
#   bash scripts/fetch-xsts.sh
#   XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTSSuiteTests
#
# Override the destination directory with XSTS_DEST (default /private/tmp/xsts).

set -euo pipefail

dest="${XSTS_DEST:-/private/tmp/xsts}"
root="$dest/xmlschema2006-11-06"
url="https://www.w3.org/XML/2004/xml-schema-test-suite/xmlschema2006-11-06/xsts-2007-06-20.tar.gz"
sha256="902176b25e4111cf96b08663107521a4992e8ea67aad6b815592a6a5b4b9ea06"

if [ -f "$root/suite.xml" ]; then
  echo "xsts: already present at $root"
  echo "xsts: export XSTS_ROOT=$root"
  exit 0
fi

mkdir -p "$dest"
archive="$dest/xsts-2007-06-20.tar.gz"
script_dir="$(cd "$(dirname "$0")" && pwd)"
vendored="$script_dir/../Tests/Fixtures/xsts/xsts-2007-06-20.tar.gz"
if [ -f "$vendored" ]; then
  echo "xsts: using the vendored archive (no download)"
  cp "$vendored" "$archive"
else
  echo "xsts: downloading the 2006-11-06 archive (about 4.4 MB)"
  curl -fsSL -o "$archive" "$url"
fi

# Verify integrity before extracting (portable across macOS and Linux).
if command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$archive" | awk '{print $1}')"
else
  echo "xsts: no sha256 tool (shasum or sha256sum) found" >&2
  rm -f "$archive"
  exit 1
fi

if [ "$actual" != "$sha256" ]; then
  echo "xsts: checksum mismatch, refusing to extract" >&2
  echo "  expected $sha256" >&2
  echo "  actual   $actual" >&2
  rm -f "$archive"
  exit 1
fi

tar xzf "$archive" -C "$dest"
rm -f "$archive"

if [ ! -f "$root/suite.xml" ]; then
  echo "xsts: suite.xml not found after extraction at $root" >&2
  exit 1
fi

echo "xsts: ready at $root"
echo "xsts: export XSTS_ROOT=$root"
