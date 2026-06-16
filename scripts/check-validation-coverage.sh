#!/usr/bin/env bash
# validation-rules.md gate: every public type under a WATCH_NS namespace is either
# a SUBJECT, an EXCLUDE entry, or covered by EXCLUDE_NS. Fails naming any gap.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
registry="$root/docs/validation-coverage-registry.txt"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

subjects="$scratch/subjects"
excludes="$scratch/excludes"
exclude_ns="$scratch/exclude_ns"
watch_ns="$scratch/watch_ns"
discovered="$scratch/discovered"

grep -E '^SUBJECT ' "$registry" | awk '{print $2}' | sort -u >"$subjects"
grep -E '^EXCLUDE ' "$registry" | awk '{print $2}' | sort -u >"$excludes"
grep -E '^EXCLUDE_NS ' "$registry" | awk '{print $2}' | sort -u >"$exclude_ns"
grep -E '^WATCH_NS ' "$registry" | awk '{print $2}' | sort -u >"$watch_ns"

: >"$discovered"
for dir in "$root"/Sources/*/; do
  folder="$(basename "$dir")"
  case "$folder" in
    Model|Parsing|Emitting|Decoding|Encoding|Validation|Stream|XPath|Pattern|XPointer|Catalog|XInclude|Canonical|Regex|Schema|XSLT|HTML)
      prefix="PureXML.$folder"
      ;;
    *) continue ;;
  esac
  rg -N '^\s+(?:public\s+)?(?:(?:final|indirect)\s+)*(struct|enum|class|actor|protocol)\s+([A-Za-z_]\w*)' "$dir" \
    -r "$prefix.\$2" -o --no-filename 2>/dev/null >>"$discovered" || true
done
sort -u "$discovered" -o "$discovered"

missing=0
while IFS= read -r qualified; do
  [[ -z "$qualified" ]] && continue
  if grep -qxF "$qualified" "$subjects" || grep -qxF "$qualified" "$excludes"; then
    continue
  fi
  ns="${qualified%.*}"
  if grep -qxF "$ns" "$exclude_ns"; then
    continue
  fi
  if grep -qxF "$ns" "$watch_ns"; then
    echo "validation-coverage: unclassified public type $qualified (add SUBJECT or EXCLUDE to docs/validation-coverage-registry.txt)" >&2
    missing=1
  fi
done <"$discovered"

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "validation-coverage: OK ($(wc -l <"$discovered" | tr -d ' ') public types scanned)"
