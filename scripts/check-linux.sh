#!/usr/bin/env bash

set -euo pipefail

run_linux_gate() {
  if [ -n "${SWIFTLY_HOME_DIR:-}" ] && [ -f "$SWIFTLY_HOME_DIR/env.sh" ]; then
    # shellcheck source=/dev/null
    . "$SWIFTLY_HOME_DIR/env.sh"
  fi
  swift --version
  swift build
  swift test
  swift build -c release
  swift test -c release
}

if [ "$(uname -s)" = "Linux" ]; then
  run_linux_gate
  exit 0
fi

HOST="${PUREYAML_LINUX_HOST:-claw}"
LIMA_INSTANCE="${PUREYAML_LIMA_INSTANCE:-debian}"
REMOTE_PARENT="${PUREYAML_LINUX_REMOTE_PARENT:-/Volumes/ClawSSD/tmp}"
REMOTE_DIR="$REMOTE_PARENT/purexml-linux-check"
REMOTE_SWIFTLY_HOME="${PUREYAML_LINUX_SWIFTLY_HOME:-/Volumes/ClawSSD/swiftly-linux/home}"
REMOTE_SWIFTLY_BIN="${PUREYAML_LINUX_SWIFTLY_BIN:-/Volumes/ClawSSD/swiftly-linux/bin}"

if ! command -v ssh >/dev/null 2>&1; then
  echo "linux: ssh is required outside Linux" >&2
  exit 2
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "linux: rsync is required outside Linux" >&2
  exit 2
fi

ssh "$HOST" "command -v limactl >/dev/null && mkdir -p '$REMOTE_DIR'"
rsync -a --delete \
  --exclude '.build' \
  --exclude '.git' \
  ./ "$HOST:$REMOTE_DIR/"

ssh "$HOST" "limactl start '$LIMA_INSTANCE' >/tmp/purexml-lima-start.log 2>&1 || true; limactl shell '$LIMA_INSTANCE' -- bash -lc 'export SWIFTLY_HOME_DIR=\"$REMOTE_SWIFTLY_HOME\" SWIFTLY_BIN_DIR=\"$REMOTE_SWIFTLY_BIN\"; [ -f \"\$SWIFTLY_HOME_DIR/env.sh\" ] && . \"\$SWIFTLY_HOME_DIR/env.sh\"; cd \"$REMOTE_DIR\" && swift --version && swift build && swift test && swift build -c release && swift test -c release'"
