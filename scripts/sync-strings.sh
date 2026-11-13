#!/bin/sh
# Gleicht die String-Kataloge mit dem Code ab.
#
# `xcodebuild build` zieht neue Texte nicht in den Katalog; das macht nur
# Xcode selbst oder der Lokalisierungs-Export. Dieses Skript stösst den
# Export an: er schreibt neue Texte nach Skywave/Localizable.xcstrings und
# markiert verschwundene als «stale». Danach fehlende Übersetzungen
# ergänzen — der Test `CatalogCompletenessTests` zeigt, welche.
set -eu
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcodegen generate >/dev/null
xcodebuild -exportLocalizations -project Skywave.xcodeproj \
    -localizationPath "$OUT" -exportLanguage en >/dev/null
git status --short Skywave/Localizable.xcstrings Skywave/InfoPlist.xcstrings
