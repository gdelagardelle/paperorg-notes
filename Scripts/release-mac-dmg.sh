#!/usr/bin/env bash
# Build, sign (Developer ID), optionally notarize, and pack Paperorg Notes for Mac direct download.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="PaperorgNotesMac"
ARCHIVE_PATH="$ROOT/build/PaperorgNotesMac.xcarchive"
EXPORT_DIR="$ROOT/build/mac-direct"
DMG_PATH="$ROOT/build/PaperorgNotes-mac.dmg"
TEAM_ID="${DEVELOPMENT_TEAM:-CZY6SHVSXB}"
DERIVED_DATA="$ROOT/build/DerivedDataMacRelease"
UNSIGNED_DMG="$ROOT/build/PaperorgNotes-mac-unsigned.dmg"
SIGNING_NOTE="$ROOT/build/mac-direct/SIGNING.txt"

cd "$ROOT"

echo "→ Regenerating Xcode project"
xcodegen generate

APP_PATH=""
if [[ "${RELEASE_SIGNING:-auto}" != "unsigned" ]]; then
  echo "→ Archiving $SCHEME (Release, signed)"
  if xcodebuild archive \
    -project PaperorgNotes.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic; then
    echo "→ Exporting Developer ID signed app"
    rm -rf "$EXPORT_DIR"
    if xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_DIR" \
      -exportOptionsPlist "$ROOT/ExportOptionsMacDirect.plist" \
      -allowProvisioningUpdates; then
      APP_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.app' | head -1)"
    fi
  fi
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "→ Signed export unavailable; building ad-hoc Release (local testing only)"
  LOCAL_DERIVED="$ROOT/build/DerivedDataMacLocal"
  xcodebuild \
    -project PaperorgNotes.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$LOCAL_DERIVED" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_ENTITLEMENTS="PaperorgNotesMac/Resources/PaperorgNotesMac.local.entitlements" \
    DEVELOPMENT_TEAM= \
    build
  APP_PATH="$(find "$LOCAL_DERIVED/Build/Products/Release" -maxdepth 1 -name '*.app' | head -1)"
  rm -rf "$EXPORT_DIR"
  mkdir -p "$EXPORT_DIR"
  cp -R "$APP_PATH" "$EXPORT_DIR/"
  APP_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.app' | head -1)"
  xattr -cr "$APP_PATH" 2>/dev/null || true
  DMG_PATH="$UNSIGNED_DMG"
  cat > "$SIGNING_NOTE" <<'EOF'
This build is ad-hoc signed for local testing (no iCloud entitlements).

For a direct-download release:
1. In Xcode, select PaperorgNotesMac and Product → Build once (creates Mac profile for com.paperorg.voicenotes.mac).
2. Create a Developer ID Application certificate for team CZY6SHVSXB.
3. Re-run: ./Scripts/release-mac-dmg.sh
4. Optional notarization: NOTARY_APPLE_ID + NOTARY_PASSWORD
EOF
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Build failed: no .app produced" >&2
  exit 1
fi

if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
  echo "→ Verifying code signature"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
  echo "→ Skipping signature verification (unsigned build)"
fi

if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  echo "→ Notarizing (NOTARY_APPLE_ID set)"
  ZIP_PATH="$EXPORT_DIR/PaperorgNotes-notarize.zip"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$NOTARY_APPLE_ID" \
    --password "$NOTARY_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait
  xcrun stapler staple "$APP_PATH"
  echo "→ Notarization complete"
else
  echo "→ Skipping notarization (set NOTARY_APPLE_ID + NOTARY_PASSWORD to enable)"
fi

echo "→ Creating DMG"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Paperorg Notes" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo ""
echo "Done."
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
echo ""
echo "Gatekeeper tip: distribute the DMG after notarization so macOS opens it without extra steps."
