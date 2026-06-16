#!/usr/bin/env bash
# validation-rules.md field-coverage gate: docs/validation-field-registry.txt must
# classify every stored property on validation document/subject types.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
registry="$root/docs/validation-field-registry.txt"
fixture="$root/Tests/Fixtures/validation-field-registry.txt"

if [[ ! -f "$registry" ]]; then
  echo "validation-field-coverage: missing $registry" >&2
  exit 1
fi

if [[ ! -f "$fixture" ]]; then
  echo "validation-field-coverage: missing $fixture (copy docs registry for WASI tests)" >&2
  exit 1
fi

if ! diff -q "$registry" "$fixture" >/dev/null 2>&1; then
  echo "validation-field-coverage: docs and Tests/Fixtures registries differ" >&2
  diff -u "$registry" "$fixture" >&2 || true
  exit 1
fi

# Lightweight structural check before the Swift meta-test runs in the suite.
models="$(grep -E '^MODEL ' "$registry" | awk '{print $2}' | sort -u)"
if [[ -z "$models" ]]; then
  echo "validation-field-coverage: registry contains no MODEL entries" >&2
  exit 1
fi

while IFS= read -r model; do
  [[ -z "$model" ]] && continue
  fields="$(awk -v model="$model" '
    $1 == "MODEL" && $2 == model { active=1; next }
    $1 == "MODEL" { active=0 }
    active && ($1 == "FIELD" || $1 == "CASE" || $1 == "IGNORE") { count++ }
    END { print count+0 }
  ' "$registry")"
  if [[ "$fields" -eq 0 ]]; then
    echo "validation-field-coverage: $model has no FIELD/CASE/IGNORE entries" >&2
    exit 1
  fi
done <<<"$models"

echo "validation-field-coverage: OK ($(wc -l <"$registry" | tr -d ' ') registry lines, $(echo "$models" | wc -l | tr -d ' ') models)"
