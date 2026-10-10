#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Open Ledger App Flutter — E2E test runner
#
# Usage:
#   ./tests/e2e/run.sh                    # run all flows
#   ./tests/e2e/run.sh import             # run single flow
#   ./tests/e2e/run.sh --fresh            # uninstall + install before tests
#   ./tests/e2e/run.sh --device emulator-5554
#
# Requires:
#   - Maestro CLI (https://maestro.mobile.dev)
#   - Android device connected (adb)
#   - APK built (flutter build apk --debug)
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLOWS_DIR="$SCRIPT_DIR/maestro"

# ── Config ────────────────────────────────────────────────────────────────────
APP_ID="app.openledger.mobile"
APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
FLUTTER="${FLUTTER_HOME:-$HOME/flutter}/bin/flutter"
ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"

# ── Args ──────────────────────────────────────────────────────────────────────
FRESH=false
DEVICE=""
FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh)    FRESH=true; shift ;;
    --device)   DEVICE="$2"; shift 2 ;;
    --help|-h)  sed -n '3,12p' "$0"; exit 0 ;;
    *)          FILTER="$1"; shift ;;
  esac
done

ADB_CMD="$ADB"
[[ -n "$DEVICE" ]] && ADB_CMD="$ADB -s $DEVICE"

# ── Pre-flight checks ─────────────────────────────────────────────────────────

echo "🔍 Checking prerequisites..."

if ! command -v maestro &>/dev/null; then
  echo "❌ Maestro CLI not found. Install: curl -Ls https://get.maestro.mobile.dev | bash"
  exit 1
fi

echo "   maestro: $(maestro --version 2>/dev/null || echo 'unknown')"

if ! "$ADB_CMD" get-state &>/dev/null; then
  echo "❌ No Android device connected (adb)."
  echo "   Connect a device or use --device <serial>"
  exit 1
fi
echo "   device: $("$ADB_CMD" get-serialno)"

# ── Fresh install ─────────────────────────────────────────────────────────────

if [[ "$FRESH" == true ]]; then
  echo ""
  echo "📦 Fresh install mode..."

  if [[ ! -f "$APK_PATH" ]]; then
    echo "   APK not found at $APK_PATH"
    echo "   Building..."
    (cd "$PROJECT_DIR" && "$FLUTTER" build apk --debug)
  fi

  echo "   Uninstalling..."
  "$ADB_CMD" uninstall "$APP_ID" 2>/dev/null || true

  echo "   Installing..."
  "$ADB_CMD" install "$APK_PATH"
fi

# ── Collect Maestro flows ─────────────────────────────────────────────────────

echo ""
echo "🧪 Running Maestro flows..."

FLOWS=()
if [[ -n "$FILTER" ]]; then
  MATCH="$FLOWS_DIR/$FILTER*.yaml"
  if ls "$MATCH" &>/dev/null; then
    mapfile -t FLOWS < <(ls "$MATCH")
  else
    echo "❌ No flow matching '$FILTER' in $FLOWS_DIR"
    exit 1
  fi
else
  mapfile -t FLOWS < <(ls "$FLOWS_DIR"/*.yaml)
fi

# ── Execute flows ─────────────────────────────────────────────────────────────

PASS=0
FAIL=0
FAILED_FLOWS=()

for flow in "${FLOWS[@]}"; do
  name="$(basename "$flow" .yaml)"
  echo ""
  echo "━━━ $name ━━━"

  DEVICE_ARG=()
  [[ -n "$DEVICE" ]] && DEVICE_ARG=(--device "$DEVICE")

  if maestro test "$flow" "${DEVICE_ARG[@]}"; then
    echo "  ✅ $name PASSED"
    ((PASS++))
  else
    echo "  ❌ $name FAILED"
    ((FAIL++))
    FAILED_FLOWS+=("$name")
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════"

if [[ ${#FAILED_FLOWS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed flows:"
  for f in "${FAILED_FLOWS[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
