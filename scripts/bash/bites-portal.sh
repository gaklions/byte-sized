#!/usr/bin/env bash
# bites-portal.sh — launch the byte-sized review portal (local web UI).
#
# Usage:
#   bites-portal.sh [--port <N>] [--host <addr>] [--no-open]
#
# Wraps `python3 scripts/portal/bites-portal.py`. Python 3.10+ is required.
# Server is loopback-only; non-127.0.0.1 hosts are refused.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PY="$EXT_ROOT/scripts/portal/bites-portal.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "byte-sized portal: python3 is required (>= 3.10). Install it and retry." >&2
  exit 1
fi

exec python3 "$PY" "$@"
