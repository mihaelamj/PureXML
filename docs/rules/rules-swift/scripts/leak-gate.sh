#!/bin/sh
# Public-safe leak gate for this repository.
# Runs on every commit (.githooks/pre-commit) and in CI (.github/workflows/leak-gate.yml).
# It enforces only what is safe in a PUBLIC repo: no AI/tool vendor names (outside the
# two attribution rules that discuss them), no machine-absolute paths, no em dashes.
# The private project-name scrub lives in a separate private repository, listing those
# names here would itself be the leak.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail=0

# AI/tool vendor names are allowed ONLY in the attribution rules that discuss them.
VEND='\bclaude\b|anthropic|\bopenai\b|chatgpt|\bcopilot\b|\bgemini\b|antigravity'
v=$(grep -rniE "$VEND" "$ROOT" --include='*.md' 2>/dev/null | grep -vE '/\.git/' \
      | grep -vE '(^|[./])(commits|git-discipline)\.md:' || true)
[ -n "$v" ] && { echo "LEAK GATE FAIL (vendor name outside attribution rules):"; echo "$v" | head; fail=1; }

# Machine-absolute paths leak a local filesystem layout.
p=$(grep -rnE '/Users/|/Volumes/' "$ROOT" --include='*.md' 2>/dev/null | grep -vE '/\.git/' || true)
[ -n "$p" ] && { echo "LEAK GATE FAIL (machine-absolute path):"; echo "$p" | head; fail=1; }

# No em dashes in any tracked markdown.
e=$(grep -rlF "$(printf '\xe2\x80\x94')" "$ROOT" --include='*.md' 2>/dev/null | grep -vE '/\.git/' || true)
[ -n "$e" ] && { echo "LEAK GATE FAIL (em dash):"; echo "$e"; fail=1; }

[ "$fail" = 0 ] || { echo "LEAK GATE FAILED for $ROOT" >&2; exit 1; }
echo "leak gate clean ($(find "$ROOT" -name '*.md' -not -path '*/.git/*' | wc -l | tr -d ' ') md files)"
