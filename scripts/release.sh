#!/bin/zsh
# Build, notarize and package Skywave for distribution (H4).
#
# Produces build/Skywave-<version>.dmg — signed, notarized and stapled,
# ready for manual distribution (Gatekeeper-clean without the App Store).
#
# One-time setup (interactive, needs an app-specific password from
# https://account.apple.com — NOT the Apple ID password itself):
#   xcrun notarytool store-credentials skywave-notary \
#     --apple-id <your-apple-id> --team-id MS6HQ7BNA9
#
# Without that keychain profile the script stops after the signed export.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO/build"
PROFILE="skywave-notary"
IDENTITY="Developer ID Application"

cd "$REPO"
xcodegen generate

VERSION=$(sed -n 's/ *MARKETING_VERSION: //p' project.yml | head -1)
ARCHIVE="$BUILD/Skywave.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/Skywave.app"
DMG="$BUILD/Skywave-$VERSION.dmg"

rm -rf "$BUILD"

echo "==> Archiving Skywave $VERSION (Release)"
xcodebuild -project Skywave.xcodeproj -scheme Skywave \
  -configuration Release archive -archivePath "$ARCHIVE" -quiet

echo "==> Exporting Developer ID signed app"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/exportOptions.plist \
  -exportPath "$EXPORT" -quiet
codesign --verify --strict --deep "$APP"

echo "==> Verifying bundled helpers (ardopcf, rigctld)"
# Each must be universal, Developer ID signed with hardened runtime, and
# carry the sandbox-inherit entitlements (child of a sandboxed app).
# Capture each tool's full output before matching. Piping straight into
# `grep -q` lets grep close the pipe on its first match; under `pipefail`
# the upstream tool then dies with SIGPIPE (141) and fails the check even
# though the pattern matched (the runtime flag prints near the top).
for NAME in ardopcf rigctld; do
  HELPER="$APP/Contents/MacOS/$NAME"
  test -f "$HELPER" || { echo "STOP: bundled $NAME missing"; exit 1; }
  HELPER_ARCHS=$(lipo -archs "$HELPER")
  [[ "$HELPER_ARCHS" == *"x86_64 arm64"* ]] \
    || { echo "STOP: $NAME is not a universal binary"; exit 1; }
  HELPER_ENTS=$(codesign -d --entitlements - "$HELPER" 2>/dev/null)
  [[ "$HELPER_ENTS" == *"com.apple.security.inherit"* ]] \
    || { echo "STOP: $NAME lacks the inherit entitlement"; exit 1; }
  HELPER_SIG=$(codesign -dv "$HELPER" 2>&1)
  [[ "$HELPER_SIG" == *"(runtime)"* ]] \
    || { echo "STOP: $NAME lacks hardened runtime"; exit 1; }
done

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "==> STOP: no notary credentials (profile '$PROFILE')."
  echo "    Signed app is at $APP — run the store-credentials command"
  echo "    from the header of this script once, then re-run it."
  exit 1
fi

echo "==> Notarizing app"
ditto -c -k --keepParent "$APP" "$BUILD/Skywave.zip"
xcrun notarytool submit "$BUILD/Skywave.zip" \
  --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

echo "==> Building DMG"
STAGE="$BUILD/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Skywave $VERSION" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"
codesign --sign "$IDENTITY" "$DMG"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> Gatekeeper check"
spctl --assess --type open --context context:primary-signature -v "$DMG"
spctl --assess --type exec -v "$APP"

echo "Release ready: $DMG"
