#!/bin/sh
# Injects the Winlink Web Services access key into the built app.
#
# The key is never stored in the repository. It is read from
# SKYWAVE_WEBSERVICE_KEY or from ~/.config/skywave/webservice-key,
# XOR-masked and written straight into the built bundle's Resources —
# so nothing generated ever sits in the source tree and nothing can be
# committed by accident.
#
# The mask is obfuscation, not encryption: it keeps the key out of a
# plain `strings` sweep over the DMG, no more. The pad must stay
# byte-identical to WebServiceKey.pad in Skywave/Support/WebServiceKey.swift.
set -eu

PAD="ch.hb9hji.skywave.webservice.v1"
BLOB_NAME="wsk.dat"

if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    DEST_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
else
    echo "warning: not running inside Xcode, nothing to do" >&2
    exit 0
fi

KEY="${SKYWAVE_WEBSERVICE_KEY:-}"
KEY_FILE="${SKYWAVE_WEBSERVICE_KEY_FILE:-$HOME/.config/skywave/webservice-key}"
if [ -z "$KEY" ] && [ -r "$KEY_FILE" ]; then
    KEY=$(tr -d '\r\n' < "$KEY_FILE")
fi

mkdir -p "$DEST_DIR"
BLOB="$DEST_DIR/$BLOB_NAME"

if [ -z "$KEY" ]; then
    # No key configured: leave the app without one. It then falls back to
    # the built-in starter list, so a fresh clone still builds and runs.
    rm -f "$BLOB"
    echo "note: no Winlink web-service key configured — Skywave will use the built-in gateway list"
    exit 0
fi

KEY="$KEY" PAD="$PAD" BLOB="$BLOB" /usr/bin/python3 - <<'PY'
import os

key = os.environ["KEY"].encode("utf-8")
pad = os.environ["PAD"].encode("utf-8")
masked = bytes(b ^ pad[i % len(pad)] for i, b in enumerate(key))
with open(os.environ["BLOB"], "wb") as blob:
    blob.write(masked)
PY

echo "note: Winlink web-service key injected (${#KEY} characters)"
