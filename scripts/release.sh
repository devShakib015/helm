#!/bin/bash
#
# Helm release builder — produces a distributable DMG.
#
#   ./scripts/release.sh
#
# The script adapts to whatever credentials this Mac has:
#
#   1. Developer ID cert + notary profile  → signed, notarized, stapled DMG.
#      Installs anywhere with zero warnings. This is the shippable artifact.
#   2. Developer ID cert only              → signed DMG, NOT notarized.
#      macOS still warns; run the notary step later to fix.
#   3. Neither                             → ad-hoc DMG for personal use.
#      Other Macs show "cannot be verified" and need a manual override.
#
# One-time setup for full notarization (needs a paid Apple Developer account):
#
#   xcrun notarytool store-credentials "helm-notary" \
#     --apple-id "you@example.com" \
#     --team-id "YOURTEAMID" \
#     --password "app-specific-password"   # appleid.apple.com ▸ Sign-In and Security
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="Helm"
NOTARY_PROFILE="${HELM_NOTARY_PROFILE:-helm-notary}"
VERSION="$(grep '^version:' pubspec.yaml | sed 's/version: *//' | cut -d'+' -f1)"

BUILD_APP="build/macos/Build/Products/Release/${APP_NAME}.app"
DIST="dist"
STAGE="${DIST}/stage"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

bold "Helm ${VERSION} — release build"

# ---------------------------------------------------------------- credentials
# Prefer an explicit identity via HELM_SIGN_ID; otherwise find a Developer ID.
SIGN_ID="${HELM_SIGN_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 \
    | sed -E 's/.*"(.*)"/\1/' || true)"
fi

CAN_NOTARIZE=false
if [[ -n "$SIGN_ID" ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  CAN_NOTARIZE=true
fi

if [[ -n "$SIGN_ID" ]]; then
  ok "Signing identity: ${SIGN_ID}"
  $CAN_NOTARIZE && ok "Notary profile: ${NOTARY_PROFILE}" \
                || warn "No notary profile '${NOTARY_PROFILE}' — will sign but not notarize."
else
  warn "No 'Developer ID Application' certificate found."
  warn "Building an AD-HOC signed app: fine on this Mac, warns on every other one."
fi

# --------------------------------------------------------------------- build
step "Building release"
flutter build macos --release
[[ -d "$BUILD_APP" ]] || { echo "Build failed: $BUILD_APP missing"; exit 1; }
ok "Built ${BUILD_APP}"

# ---------------------------------------------------------------------- sign
if [[ -n "$SIGN_ID" ]]; then
  step "Signing (hardened runtime)"
  # Sign inside-out: nested code must be signed before the bundle that holds
  # it. `--deep` is deprecated and gets notarization rejected, so walk it.
  while IFS= read -r item; do
    codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$item"
  done < <(find "$BUILD_APP/Contents/Frameworks" \
              \( -name '*.dylib' -o -name '*.framework' \) -maxdepth 1 2>/dev/null || true)

  # Any helper executables bundled alongside the main binary.
  while IFS= read -r helper; do
    codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$helper"
  done < <(find "$BUILD_APP/Contents/MacOS" -type f -perm +111 \
              ! -name "$APP_NAME" 2>/dev/null || true)

  codesign --force --timestamp --options runtime \
    --entitlements macos/Runner/Release.entitlements \
    --sign "$SIGN_ID" "$BUILD_APP"

  codesign --verify --strict --verbose=2 "$BUILD_APP" 2>&1 | tail -2
  ok "Signed and verified"
fi

# ------------------------------------------------------------------ notarize
if $CAN_NOTARIZE; then
  step "Notarizing app (Apple review, usually 1–5 min)"
  NOTARY_ZIP="${DIST}/${APP_NAME}-notarize.zip"
  mkdir -p "$DIST"
  ditto -c -k --keepParent "$BUILD_APP" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$BUILD_APP"
  rm -f "$NOTARY_ZIP"
  ok "Notarized and stapled"
fi

# ----------------------------------------------------------------------- dmg
step "Packaging DMG"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$BUILD_APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -quiet \
  "$DMG"
rm -rf "$STAGE"
ok "Created ${DMG}"

# The DMG itself is also signed + notarized so the download never warns.
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
  ok "Signed DMG"
fi
if $CAN_NOTARIZE; then
  step "Notarizing DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  ok "Notarized and stapled DMG"
fi

# -------------------------------------------------------------------- report
step "Result"
SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "  $DMG  (${SIZE})"

if $CAN_NOTARIZE; then
  # Gatekeeper's verdict on a freshly downloaded copy.
  if spctl -a -vvv -t install "$BUILD_APP" 2>&1 | grep -q "accepted"; then
    ok "Gatekeeper: accepted — installs cleanly on any Mac"
  fi
  echo
  bold "Ready to publish. 🚢"
else
  echo
  warn "This DMG is NOT notarized — other Macs will show a security warning."
  if [[ -z "$SIGN_ID" ]]; then
    echo "  To ship publicly you need a paid Apple Developer account (\$99/yr),"
    echo "  a 'Developer ID Application' certificate, then re-run this script."
  else
    echo "  Store notary credentials (see the header of this script), then re-run."
  fi
fi
