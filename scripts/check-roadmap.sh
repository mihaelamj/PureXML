#!/usr/bin/env bash
# Mermaid roadmap gate. Keeps README roadmap diagrams vertical, legend-first,
# TileDown-palette colored, and covered by live epic issues.
# See docs/rules/mermaid.md.

set -u

README="README.md"
FAIL=0

fail() {
  echo "roadmap: $1" >&2
  FAIL=1
}

expected_classes() {
  cat <<'EOF'
  classDef done fill:#ddf9e4,stroke:#34c759,color:#111827
  classDef review fill:#fff7d6,stroke:#ffcc00,color:#111827
  classDef epic fill:#f2e5ff,stroke:#af52de,color:#111827
  classDef todo fill:#f2f4f7,stroke:#8e8e93,color:#111827
EOF
}

known_class() {
  case "$1" in
    done|review|epic|todo) return 0 ;;
    *) return 1 ;;
  esac
}

extract_blocks() {
  awk -v dir="$1" '
    /^```mermaid$/ {
      inside = 1
      count += 1
      file = sprintf("%s/block-%03d.mmd", dir, count)
      next
    }
    /^```$/ {
      if (inside == 1) {
        inside = 0
        file = ""
      }
      next
    }
    inside == 1 {
      print > file
    }
    END {
      count_file = dir "/count"
      print count + 0 > count_file
    }
  ' "$README"
}

node_defined() {
  grep -Fxq "$1" "$2"
}

validate_block() {
  block="$1"
  index="$2"
  defined_nodes="$3"
  expected="$4"
  defs="$5"

  grep '^  classDef ' "$block" > "$defs" || true
  if ! diff -u "$expected" "$defs" >/dev/null; then
    fail "mermaid block $index must use the TileDown Mermaid color classDefs"
  fi

  : > "$defined_nodes"
  saw_non_class_def=0

  while IFS= read -r line || [ -n "$line" ]; do
    trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$trimmed" in
      ""|"flowchart "*|"%%"*) continue ;;
    esac

    case "$trimmed" in
      classDef\ *)
        if [ "$saw_non_class_def" -ne 0 ]; then
          fail "mermaid block $index has classDef after nodes or edges"
        fi
        continue
        ;;
    esac

    saw_non_class_def=1

    if [[ "$line" =~ ^[[:space:]]*([A-Za-z][A-Za-z0-9_]*)[[:space:]]*(\[.*\]|\(.*\)|\{.*\})[[:space:]]*:::[[:space:]]*([A-Za-z][A-Za-z0-9_]*)[[:space:]]*$ ]]; then
      node="${BASH_REMATCH[1]}"
      node_class="${BASH_REMATCH[3]}"
      if ! known_class "$node_class"; then
        fail "mermaid block $index uses unknown class $node_class"
      fi
      echo "$node" >> "$defined_nodes"
      continue
    fi

    if [[ "$line" =~ (--\>|~~~) ]]; then
      if [[ "$line" =~ ^[[:space:]]*([A-Za-z][A-Za-z0-9_]*)[[:space:]]*(--\>|~~~)[[:space:]]*([A-Za-z][A-Za-z0-9_]*)[[:space:]]*$ ]]; then
        left="${BASH_REMATCH[1]}"
        right="${BASH_REMATCH[3]}"
        if ! node_defined "$left" "$defined_nodes" || ! node_defined "$right" "$defined_nodes"; then
          fail "mermaid block $index has edge with undefined node: $left to $right"
        fi
      else
        fail "mermaid block $index has unsupported edge syntax: $trimmed"
      fi
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*[A-Za-z][A-Za-z0-9_]*[[:space:]]*(\[.*\]|\(.*\)|\{.*\})[[:space:]]*$ ]]; then
      fail "mermaid block $index has unclassed node: $trimmed"
    fi
  done < "$block"

  if [ "$index" -gt 1 ] &&
    grep -Fq ':::done' "$block" &&
    ! grep -Eq ':::(todo|review|epic)' "$block"; then
    fail "mermaid block $index expands completed work; collapse completed epics to one done node"
  fi
}

repo_name() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    printf '%s\n' "$GITHUB_REPOSITORY"
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 1
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null
}

check_epic_coverage() {
  repo=$(repo_name || true)
  if [ -z "$repo" ] || ! command -v gh >/dev/null 2>&1; then
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      fail "gh is required in CI to verify epic coverage"
    else
      echo "roadmap: skipping GitHub epic coverage because gh is unavailable" >&2
    fi
    return
  fi

  numbers=$(gh issue list \
    --repo "$repo" \
    --label epic \
    --state all \
    --limit 1000 \
    --json number \
    --jq '.[].number' 2>/dev/null)
  if [ $? -ne 0 ]; then
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      fail "failed to query epic issues"
    else
      echo "roadmap: skipping GitHub epic coverage because gh issue list failed" >&2
    fi
    return
  fi

  combined="$1"
  for number in $numbers; do
    if ! grep -Fq "#$number" "$combined"; then
      fail "epic issue #$number is missing from README Mermaid diagrams"
    fi
  done
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/purexml-roadmap.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

extract_blocks "$tmp"
count=$(cat "$tmp/count")
if [ "$count" -eq 0 ]; then
  fail "README has no Mermaid blocks"
  exit "$FAIL"
fi

first="$tmp/block-001.mmd"
if ! grep -Fq 'LDone["In main now"]' "$first" || ! grep -Fq 'LTodo["Open issue, no PR"]' "$first"; then
  fail "first Mermaid block must be the shared legend"
fi

expected="$tmp/expected-classes.txt"
expected_classes > "$expected"

combined="$tmp/all-blocks.mmd"
: > "$combined"
index=1
while [ "$index" -le "$count" ]; do
  block=$(printf '%s/block-%03d.mmd' "$tmp" "$index")
  cat "$block" >> "$combined"
  validate_block \
    "$block" \
    "$index" \
    "$tmp/defined-$index.txt" \
    "$expected" \
    "$tmp/defs-$index.txt"
  index=$((index + 1))
done

check_epic_coverage "$combined"

if [ "$FAIL" -eq 0 ]; then
  echo "roadmap: OK"
fi

exit "$FAIL"
