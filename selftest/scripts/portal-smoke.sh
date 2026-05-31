#!/usr/bin/env bash
# portal-smoke.sh — boot bites-portal.py in the background against a tiny sandbox,
# curl the public routes, assert each returns 200, then stop the server.
# Used in CI to catch regressions in the Python backend or static SPA bundle.

set -euo pipefail
SELFTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_ROOT="$(cd "$SELFTEST_DIR/../.." && pwd)"
PORTAL="$EXT_ROOT/scripts/portal/bites-portal.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "portal-smoke: python3 not on PATH; skipping." >&2
  exit 0
fi

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"; [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true' EXIT

mkdir -p "$SANDBOX/.specify/extensions/byte-sized"
cp "$EXT_ROOT/config-template.yml" "$SANDBOX/.specify/extensions/byte-sized/config-template.yml"
mkdir -p "$SANDBOX/.specify/bites/domains" "$SANDBOX/.specify/bites/_drafts"
cat > "$SANDBOX/.specify/bites/index.json" <<'EOF'
{"schema_version":"1.0","generated_at":"2026-05-30T00:00:00Z","bites":[]}
EOF

PORT="${BS_PORTAL_PORT:-7821}"
cd "$SANDBOX"
python3 "$PORTAL" --port "$PORT" --no-open >/tmp/portal.log 2>&1 &
SERVER_PID=$!

# Wait until /api/config responds (5 s budget).
for _ in {1..25}; do
  if curl -fsS "http://127.0.0.1:$PORT/api/config" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

assert_route() {
  local route="$1"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$route")"
  if [[ "$code" != "200" ]]; then
    echo "portal-smoke: FAIL $route -> $code" >&2
    echo '--- server log ---' >&2; cat /tmp/portal.log >&2 || true
    exit 1
  fi
  echo "  PASS $route -> 200"
}

echo "==> portal smoke @ http://127.0.0.1:$PORT"
assert_route /
assert_route /assets/styles.css
assert_route /assets/app.js
assert_route /assets/drafts.js
assert_route /assets/graph.js
assert_route /assets/detail.js
assert_route /api/config
assert_route /api/index
assert_route /api/drafts

echo "==> loopback enforcement"
non_loop_code="$(python3 "$PORTAL" --host 0.0.0.0 --port "$PORT" --no-open --repo "$SANDBOX" 2>&1 || true | tail -n1)"
# The previous line invokes the server which exits non-zero immediately; capture exit code separately.
set +e
python3 "$PORTAL" --host 0.0.0.0 --port "$PORT" --no-open --repo "$SANDBOX" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "portal-smoke: FAIL non-loopback host was accepted" >&2; exit 1
fi
echo "  PASS non-loopback host refused (exit $rc)"

echo "==> portal-smoke passed"
