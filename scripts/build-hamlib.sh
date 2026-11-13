#!/bin/bash
# build-hamlib.sh
# Baut rigctld aus dem Hamlib-Quellcode als Universal2 (arm64 + x86_64),
# statisch, ohne libusb-Dependency, Ad-Hoc codesigned mit Hardened Runtime.
# Output landet in Skywave/Vendor/hamlib/rigctld.
#
# Mit diesem Ablauf ist das mitgelieferte rigctld gebaut worden; der
# Xcode-Build signiert es beim Einbetten neu (siehe project.yml).
#
# Voraussetzungen: autoconf, automake, libtool, pkg-config (brew installable).
# Apple Silicon empfohlen (Rosetta für x86_64-Build-Tests nicht zwingend nötig,
# da Cross-Compile-Konfiguration verwendet wird).
#
# Reproducible Build: Hamlib-Tag ist gepinnt (HAMLIB_TAG unten).

set -euo pipefail

HAMLIB_TAG="4.7.1"
HAMLIB_REPO="https://github.com/Hamlib/Hamlib.git"
MIN_MACOS="13.0"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d -t hamlib-build-XXXXXX)"
OUT_DIR="$PROJECT_DIR/Skywave/Vendor/hamlib"
OUT_BIN="$OUT_DIR/rigctld"

# Helfer-Binaries, die aus dem Hamlib-tests/-Verzeichnis kopiert werden.
TOOLS=(rigctld)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cleanup() {
  echo -e "${YELLOW}Cleanup: $WORK_DIR${NC}"
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log() { echo -e "${GREEN}==> $*${NC}"; }
warn() { echo -e "${YELLOW}!! $*${NC}"; }
die() { echo -e "${RED}!! $*${NC}" >&2; exit 1; }

# --- Homebrew-PATH einbinden, falls vorhanden aber nicht im PATH
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# --- Vorbedingungen prüfen
log "Prüfe Build-Tools"
for tool in autoconf automake libtool glibtoolize pkg-config clang lipo codesign git; do
  command -v "$tool" >/dev/null 2>&1 || die "Fehlt: $tool (brew install autoconf automake libtool pkg-config)"
done

# --- Source klonen
log "Clone Hamlib $HAMLIB_TAG"
cd "$WORK_DIR"
git clone --branch "$HAMLIB_TAG" --depth 1 "$HAMLIB_REPO" src
cd src

log "Bootstrap (autoreconf)"
./bootstrap

# --- Configure-Flags (für beide Architekturen identisch außer -arch)
COMMON_CONFIGURE_FLAGS=(
  --enable-static
  --disable-shared
  --without-libusb
  --without-cxx-binding
  --with-pic
)

build_arch() {
  local ARCH="$1"
  local HOST_TRIPLET="$2"
  local PREFIX="$WORK_DIR/install-$ARCH"

  log "Build $ARCH"
  make distclean 2>/dev/null || true

  ./configure \
    --prefix="$PREFIX" \
    --host="$HOST_TRIPLET" \
    "${COMMON_CONFIGURE_FLAGS[@]}" \
    CC=clang \
    CFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS -O2" \
    LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS"

  make -j"$(sysctl -n hw.ncpu)"

  mkdir -p "$WORK_DIR/binaries"
  for tool in "${TOOLS[@]}"; do
    local BIN_OUT="$WORK_DIR/binaries/$tool.$ARCH"
    cp "tests/$tool" "$BIN_OUT"
    # Architektur-Verifikation
    lipo -info "$BIN_OUT" | grep -q "$ARCH" || die "Falsche Architektur in $BIN_OUT"
  done
}

# --- Beide Architekturen bauen
build_arch arm64 aarch64-apple-darwin
build_arch x86_64 x86_64-apple-darwin

# --- Lipo merge + Ad-Hoc codesign mit Hardened Runtime (je Tool)
log "Universal2 erstellen (lipo) + Ad-Hoc codesign (--options runtime)"
mkdir -p "$OUT_DIR"
for tool in "${TOOLS[@]}"; do
  lipo -create \
    -output "$OUT_DIR/$tool" \
    "$WORK_DIR/binaries/$tool.arm64" \
    "$WORK_DIR/binaries/$tool.x86_64"
  codesign --force --sign - --options runtime "$OUT_DIR/$tool"
done

# --- Verifikation
log "Verifikation"
for tool in "${TOOLS[@]}"; do
  echo
  echo "=== $tool ==="
  echo "Architekturen:"
  lipo -info "$OUT_DIR/$tool"
  echo "Dylibs (nur System-Libs erlaubt):"
  otool -L "$OUT_DIR/$tool"
  echo "Codesign:"
  codesign -dvv "$OUT_DIR/$tool" 2>&1 | head -6
done

echo
echo "Smoke-Test rigctld (Dummy-Rig, Frequenz lesen):"
"$OUT_BIN" -m 1 -t 14999 > /dev/null 2>&1 &
RIG_PID=$!
sleep 1
RESP=$(printf "f\nq\n" | nc localhost 14999 | head -1)
kill $RIG_PID 2>/dev/null || true
wait $RIG_PID 2>/dev/null || true

if [ "$RESP" = "145000000" ]; then
  echo -e "${GREEN}✓ Smoke-Test grün (rigctld antwortet: $RESP)${NC}"
else
  die "rigctld Smoke-Test fehlgeschlagen — Response: $RESP"
fi

echo
log "Fertig: $OUT_BIN ($(ls -l "$OUT_BIN" | awk '{print $5}') Bytes)"
echo
echo "Hamlib-Version: $HAMLIB_TAG"
echo "Architekturen: arm64 + x86_64 (Universal2)"
echo "Codesign: Ad-Hoc + Hardened Runtime"
echo "Lizenz-Hinweis: rigctld steht unter GPL-2.0+, die Hamlib-Bibliothek unter LGPL-2.1+;"
echo "bei Verteilung Quellstand und Lizenztexte mitliefern (Skywave/Vendor/hamlib/)."
