#!/usr/bin/env bash
# Changelog currency gate. When a change set modifies library sources under
# Sources/, it must also update CHANGELOG.md, so the Keep a Changelog
# "Unreleased" section stays current. See docs/rules/verification.md.
#
# The change set is the union of (a) commits on this branch since it forked
# from the base branch (origin/main, else main) and (b) the staged and unstaged
# working tree. With nothing to compare (a clean checkout sitting on the base
# branch) the gate is a no-op. Pure test, doc, or script edits do not require a
# changelog entry; only Sources/*.swift changes do. Set CHANGELOG_SKIP=1 to
# bypass the gate for an intentional refactor-only change with no notable effect.

set -u

CHANGELOG="CHANGELOG.md"
FAIL=0

fail() {
  echo "changelog: $1" >&2
  FAIL=1
}

if [ "${CHANGELOG_SKIP:-0}" = "1" ]; then
  echo "changelog: skipped (CHANGELOG_SKIP=1)"
  exit 0
fi

base_ref=""
for ref in origin/main main; do
  if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
    base_ref="$ref"
    break
  fi
done

changed=""
if [ -n "$base_ref" ]; then
  merge_base=$(git merge-base "$base_ref" HEAD 2>/dev/null || true)
  if [ -n "$merge_base" ]; then
    changed=$(git diff --name-only "$merge_base" HEAD)
  fi
fi
changed=$(printf '%s\n%s\n%s\n' \
  "$changed" \
  "$(git diff --cached --name-only)" \
  "$(git diff --name-only)")

source_changed=$(printf '%s\n' "$changed" | grep -E '^Sources/.*\.swift$' | sort -u)

if [ -z "$source_changed" ]; then
  echo "changelog: OK (no library source changes)"
  exit 0
fi

if printf '%s\n' "$changed" | grep -qx "$CHANGELOG"; then
  echo "changelog: OK"
  exit 0
fi

fail "library sources changed but $CHANGELOG was not updated:"
printf '%s\n' "$source_changed" | sed 's/^/  /' >&2
echo "  (add an Unreleased entry, or set CHANGELOG_SKIP=1 for a refactor-only change)" >&2

exit "$FAIL"
