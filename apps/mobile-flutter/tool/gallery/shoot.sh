#!/usr/bin/env bash
# Headless screenshot pipeline for the design gallery (ADR-005).
#
# Builds the gallery for Flutter web, serves it locally, and captures every
# scenario at 2× with headless Chrome into ../../tmp/gallery/ (repo root
# tmp/, which is gitignored). These PNGs are the input for L1 visual review
# and future golden tests.
#
# Usage:
#   tool/gallery/shoot.sh              # full rebuild + shoot
#   tool/gallery/shoot.sh --skip-build # reuse build/web
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/../.." && pwd)"
OUT_DIR="$REPO_ROOT/tmp/gallery"
PORT="${PORT:-8123}"
CHROME="${CHROME:-google-chrome}"
SIZE='390,844'
SCALE=2

cd "$APP_DIR"

if [[ "${1:-}" != "--skip-build" ]]; then
  flutter build web --no-version-check --release -t tool/gallery/main.dart
fi
mkdir -p "$OUT_DIR"

# Serve build/web.
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$APP_DIR/build/web" \
  >"$OUT_DIR/gallery_http.log" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

# Wait for the server.
for _ in $(seq 1 50); do
  if curl -sf "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

# name|route (after the hash). theme/lang/chrome are appended uniformly.
scenarios=(
  "catalog|/"
  "tokens-dark|/tokens/dark"
  "tokens-light|/tokens/light"
  "components|/components"
  "main-idle|/screens/main?bleState=idle"
  "main-ble-eth|/screens/main?chain=ethereum"
  "main-ble-sol|/screens/main?chain=solana"
  "main-ble-connected|/screens/main?chain=ethereum&bleState=connected"
  "main-ble-pending|/screens/main?pending=1"
  "main-ble-pending-panel|/screens/main?pending=1&blepanel=1"
  "main-ble-error|/screens/main?bleState=error&chain=ethereum"
  "main-ble-error-panel|/screens/main?bleState=error&chain=ethereum&blepanel=1"
  "main-ble-panel|/screens/main?blepanel=1"
  "main-ble-panel-idle|/screens/main?bleState=idle&blepanel=1"
  "main-logs|/screens/main?logs=1"
  "main-history|/screens/main?tab=1"
  "main-settings|/screens/main?tab=2"
  "main-settings-theme-sheet|/screens/main?tab=2&themeSheet=1"
  "account-eth|/account/0?chain=eth"
  "account-sol|/account/0?chain=sol"
  "account-sol-1|/account/1?chain=sol1"
  "account-btc|/account/0?chain=btc"
  "account-tron|/account/0?chain=tron"
  "account-sui|/account/0?chain=sui"
  "export-seed|/screens/export-seed"
  "export-seed-passphrase|/screens/export-seed?passphrase=1"
  "export-key-eth|/export-private-key?chain=eth"
  "export-key-btc|/export-private-key?chain=btc"
  "backup-export|/screens/backup-export"
  "backup-export-passphrase|/screens/backup-export?passphrase=1"
  "backup-export-enigma|/screens/backup-export?enigma=1"
  "private-keys|/screens/private-keys"
  "verify-seed|/screens/verify-seed?result=match"
  "verify-seed-mismatch|/screens/verify-seed?result=mismatch"
  "verify-seed-unavailable|/screens/verify-seed?result=unavailable"
  "verify-passphrase|/screens/verify-passphrase?result=mismatch"
  "verify-enigma|/screens/verify-enigma?result=match"
  "privacy-shield|/screens/privacy-shield"
  "stand-in-intro|/screens/stand-in"
  "stand-in-mnemonic|/screens/stand-in?step=mnemonic"
  "stand-in-status|/screens/stand-in?configured=1"
  "welcome|/screens/welcome"
  "entropy|/screens/entropy"
  "generate-mnemonic|/screens/generate-mnemonic"
  "verify-mnemonic|/screens/verify-mnemonic"
  "import|/screens/import"
  "enigma|/screens/enigma"
  "enigma-mnemonic|/screens/enigma-mnemonic"
  "set-pin|/screens/set-pin"
  "unlock|/screens/unlock"
  "unlock-locked|/screens/unlock?state=locked"
  "backup-seed|/screens/backup-seed"
  "transaction|/screens/transaction"
  "confirm-address|/screens/confirm-address"
  "signature-result|/screens/signature-result"
)

shoot() {
  local name="$1" route="$2" theme="$3" lang="$4"
  local url="http://127.0.0.1:$PORT/#${route}"
  local sep
  if [[ "$route" == *\?* ]]; then sep='&'; else sep='?'; fi
  url="${url}${sep}chrome=0&theme=${theme}&lang=${lang}"
  local out="$OUT_DIR/${name}__${theme}-${lang}.png"
  rm -rf "$OUT_DIR/chrome-profile-${name}"

  "$CHROME" \
    --headless=new \
    --no-sandbox \
    --no-first-run \
    --user-data-dir="$OUT_DIR/chrome-profile-${name}" \
    --hide-scrollbars \
    --force-device-scale-factor="$SCALE" \
    --window-size="$SIZE" \
    --enable-unsafe-swiftshader \
    --use-gl=angle --use-angle=swiftshader \
    --run-all-compositor-stages-before-draw \
    --virtual-time-budget=30000 \
    --screenshot="$out" \
    "$url" >/dev/null 2>&1
  echo "  $out"
}

echo "Shooting dark/zh scenarios..."
for entry in "${scenarios[@]}"; do
  shoot "${entry%%|*}" "${entry#*|}" dark zh
done
echo "Shooting light/en cross-checks..."
shoot tokens-light /tokens/light light zh
shoot components /components light en
shoot main-settings-theme-sheet "/screens/main?tab=2&themeSheet=1" light zh
shoot account-eth /account/0?chain=eth light en
# The neo chrome is light-only, so the History and Settings tabs need a light
# capture too — the dark pass above never sees their neobrutalist styling.
shoot main-history /screens/main?tab=1 light en
shoot main-settings /screens/main?tab=2 light en
# Solana's second account: the detail badge must read "Account 1" (from the
# path's 4th segment), not the list position.
shoot account-sol-1 /account/1?chain=sol1 light en
# The Vault screen has its own light-mode risks (the idle FAB's neutral disc
# sits on a white background), so the FAB states get a light cross-check too.
shoot main-idle /screens/main?bleState=idle light en
shoot main-ble-eth /screens/main?chain=ethereum light en
shoot main-ble-panel /screens/main?blepanel=1 light en
# Export screens carry their own light-mode risks: the QR sits on a white
# card that must stay distinct from a white background.
shoot export-seed /screens/export-seed light en
shoot export-seed-passphrase /screens/export-seed?passphrase=1 light en
shoot export-key-eth /export-private-key?chain=eth light en
shoot backup-export /screens/backup-export light en
shoot private-keys /screens/private-keys light en
# Verification screens: the verdict card's tinted background is the light-mode
# risk (it must stay legible on white), so capture the match state light.
shoot verify-seed /screens/verify-seed?result=match light en
shoot verify-enigma /screens/verify-enigma?result=match light en
# The privacy cover sits on a plain background — verify it is opaque (no
# secret bleeding through) in the light theme too.
shoot privacy-shield /screens/privacy-shield light en
# The stand-in wizard is new and carries its own light-mode risks (threat
# copy, mode cards, PIN pads).
shoot stand-in-intro /screens/stand-in light en
shoot stand-in-mnemonic '/screens/stand-in?step=mnemonic' light en
shoot stand-in-status '/screens/stand-in?configured=1' light en
# The onboarding, auth and signing flows are all neo in light mode, so each
# needs a light capture — the dark pass above never sees their neo chrome.
shoot welcome /screens/welcome light en
shoot unlock /screens/unlock light en
shoot unlock-locked '/screens/unlock?state=locked' light en
shoot set-pin /screens/set-pin light en
shoot entropy /screens/entropy light en
shoot generate-mnemonic /screens/generate-mnemonic light en
shoot verify-mnemonic /screens/verify-mnemonic light en
shoot import /screens/import light en
shoot enigma /screens/enigma light en
shoot enigma-mnemonic /screens/enigma-mnemonic light en
shoot backup-seed /screens/backup-seed light en
shoot transaction /screens/transaction light en
shoot confirm-address /screens/confirm-address light en
shoot signature-result /screens/signature-result light en

echo "Done → $OUT_DIR"
ls -la "$OUT_DIR"/*.png | awk '{print $5, $9}'
