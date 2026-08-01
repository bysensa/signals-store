#!/usr/bin/env bash
# dart2js smoke-тест для ReactiveStore.
# Компилирует probe в JS через `dart compile js` и выполняет через Node,
# проверяя ожидаемые маркеры в stdout. Не требует Chrome/браузера.
#
# Запуск: bash packages/signals_store/scripts/dart2js_smoke.sh
# Требования: dart, node в PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBE="$PKG_DIR/test/smoke/dart2js_smoke.dart"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "→ Compiling $PROBE via dart compile js..."
JS_OUT="$WORK_DIR/smoke.js"
( cd "$PKG_DIR" && dart compile js "$PROBE" -o "$JS_OUT" ) || {
  echo "✗ dart compile js failed" >&2
  exit 1
}

echo "→ Running compiled output via node..."
OUTPUT="$(node "$JS_OUT" 2>&1)" || {
  echo "✗ node execution failed:" >&2
  echo "$OUTPUT" >&2
  exit 1
}

echo "$OUTPUT"

# Assert expected markers.
fail=0
check() {
  local label="$1" expected="$2"
  if ! echo "$OUTPUT" | grep -q "RESULT $label=$expected"; then
    echo "✗ assertion failed: expected '$label=$expected'" >&2
    fail=1
  fi
}

check public_read 42
check private_read secret
check uninitialized field_init_error
check post_dispose state_error

if [ "$fail" -ne 0 ]; then
  echo "✗ dart2js smoke FAILED" >&2
  exit 1
fi

echo "✓ dart2js smoke PASSED"
