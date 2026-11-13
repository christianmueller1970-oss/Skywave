#!/bin/zsh
# Publish a built, notarized Skywave DMG as a Sparkle auto-update.
#
# Steps:
#   1. EdDSA-sign build/Skywave-<version>.dmg with the private key in the
#      login keychain (paired with SUPublicEDKey in the app's Info.plist).
#   2. Create a GitHub release in the PUBLIC Skywave-releases repo with the
#      DMG attached as an asset (that is the download Sparkle fetches).
#   3. Add an <item> for this version to appcast.xml (the Sparkle feed) in
#      that repo and push it.
#
# Run AFTER scripts/release.sh has produced the notarized DMG. Kept separate
# from release.sh on purpose: building must never auto-publish to the public
# channel — you decide when an update goes live.
#
# One-time: the signing key already lives in the keychain (generate_keys).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO/build"
RELEASES_REPO="christianmueller1970-oss/Skywave-releases"
SPARKLE_VERSION="2.9.4"
TOOLS="$BUILD/sparkle-tools"

VERSION=$(sed -n 's/ *MARKETING_VERSION: //p' "$REPO/project.yml" | head -1)
BUILDNUM=$(sed -n 's/ *CURRENT_PROJECT_VERSION: //p' "$REPO/project.yml" | head -1)
DMG="$BUILD/Skywave-$VERSION.dmg"
TAG="v$VERSION"
DL_URL="https://github.com/$RELEASES_REPO/releases/download/$TAG/Skywave-$VERSION.dmg"

test -f "$DMG" || { echo "STOP: $DMG not found — run scripts/release.sh first"; exit 1; }

# --- Sparkle CLI tools (sign_update), cached under build/ ---
if [[ ! -x "$TOOLS/bin/sign_update" ]]; then
  echo "==> Fetching Sparkle $SPARKLE_VERSION tools"
  mkdir -p "$TOOLS"
  gh release download "$SPARKLE_VERSION" --repo sparkle-project/Sparkle \
    --pattern "Sparkle-*.tar.xz" --dir "$TOOLS" --clobber
  tar -xf "$TOOLS"/Sparkle-*.tar.xz -C "$TOOLS"
fi

echo "==> Signing $DMG"
SIGINFO=$("$TOOLS/bin/sign_update" "$DMG")   # sparkle:edSignature="..." length=NNNN
echo "    $SIGINFO"

echo "==> Updating appcast.xml"
WORK="$BUILD/releases-repo"
rm -rf "$WORK"
gh repo clone "$RELEASES_REPO" "$WORK" -- --depth 1 >/dev/null 2>&1
APPCAST="$WORK/appcast.xml"

if [[ ! -f "$APPCAST" ]]; then
  cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Skywave</title>
    <link>https://raw.githubusercontent.com/$RELEASES_REPO/main/appcast.xml</link>
    <description>Skywave — Winlink für macOS: Update-Feed</description>
    <language>de</language>
  </channel>
</rss>
EOF
fi

# RFC 822 needs English day and month names; with a German locale `date`
# wrote "Do., 12 Nov." into the feed (0.6.0 and 0.7.0).
PUBDATE=$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")
ITEM="    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILDNUM</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>$PUBDATE</pubDate>
      <enclosure url=\"$DL_URL\" $SIGINFO type=\"application/octet-stream\" />
    </item>"

# Insert the new <item> before </channel>. Skip if this build number is
# already present so re-runs stay idempotent. Sparkle picks the highest
# sparkle:version regardless of item order, so insertion position is safe.
BUILDNUM="$BUILDNUM" VERSION="$VERSION" ITEM="$ITEM" python3 - "$APPCAST" <<'PY'
import os, sys
path = sys.argv[1]
xml = open(path, encoding="utf-8").read()
marker = f"<sparkle:version>{os.environ['BUILDNUM']}</sparkle:version>"
if marker in xml:
    print(f"    appcast already has build {os.environ['BUILDNUM']}, leaving it")
else:
    xml = xml.replace("  </channel>", os.environ["ITEM"] + "\n  </channel>", 1)
    open(path, "w", encoding="utf-8").write(xml)
    print(f"    added item for {os.environ['VERSION']} (build {os.environ['BUILDNUM']})")
PY

cd "$WORK"
if [[ -n "$(git status --porcelain appcast.xml)" ]]; then
  git add appcast.xml
  git commit -q -m "Appcast: Skywave $VERSION (build $BUILDNUM)"
  # First push into a fresh repo must create the main branch.
  git branch -M main
  git push -q -u origin main
  echo "==> appcast.xml pushed"
else
  echo "==> appcast.xml unchanged"
fi

# Create the release only now: GitHub refuses a release on an empty repo,
# and the appcast push above has seeded main.
echo "==> Creating GitHub release $TAG in $RELEASES_REPO"
if gh release view "$TAG" --repo "$RELEASES_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" --repo "$RELEASES_REPO" --clobber
else
  gh release create "$TAG" "$DMG" --repo "$RELEASES_REPO" \
    --title "Skywave $VERSION" --notes "Skywave $VERSION"
fi

echo
echo "Published Skywave $VERSION"
echo "  DMG:     $DL_URL"
echo "  Appcast: https://raw.githubusercontent.com/$RELEASES_REPO/main/appcast.xml"
