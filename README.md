# Skywave

A small, fully native macOS client for [Winlink](https://winlink.org) mail —
read and send Winlink messages over the internet (telnet/CMS), no Windows
box, no extra hardware.

Built on [WinlinkKit](https://github.com/christianmueller1970-oss/WinlinkKit),
the native Swift implementation of the Winlink B2F protocol.

**Status: stable — in regular on-air use.** Milestones:

- ✅ H0 — app scaffold (SwiftUI shell, WinlinkKit linked)
- ✅ H1 — mailbox persistence, Keychain, settings (callsign/password/locator)
- ✅ H2 — mail UI (inbox/outbox/sent, reading pane, compose window)
- ✅ H3 — exchange over telnet with progress and error handling
- ✅ H4 — Developer ID signing, notarization, DMG for manual distribution
- ✅ H5 — radio transports (VARA/ARDOP via external TNC, rigctld PTT)
- ✅ H6 — bundled ardopcf modem (integrated TNC, one USB cable to the
  rig) — **on-air test passed 2026-07-18**: HB9AK via 80 m (3'613 kHz
  dial, ARDOP 2000), automatic CI-V QSY with frequency restore, CAT
  PTT, ARQ connect quality 99, full B2F exchange, 12/12 frame syncs,
  0 failed decodes. Note: RTS PTT (`TIOCMSET`) is blocked by the app
  sandbox — CAT (CI-V) PTT is the supported mode for the bundled TNC.
- ✅ H7 — gateway directory from the Winlink Web Services (nearby RMS
  gateways per band with distance, bearing and favourites)
- ✅ H8 — rig control through a bundled Hamlib rigctld (Settings →
  Funkgerät: model and port, live frequency and mode, PTT and QSY over
  one connection; direct CI-V and an external rigctld remain under
  «Erweitert») — **on-air test passed 2026-11-12** with an IC-7300
- ✅ H9 — one main window with sections in the sidebar (mailbox, radio,
  tools), complete menu bar, labelled toolbar, connection history and
  session logs; German or English user interface, chosen in Settings

## Gateway directory

Ablage ▸ Gateways (⇧⌘G) lists the RMS gateways near your locator with
distance, bearing, band and bandwidth, with favourites and a band
filter. The list comes from the Winlink Web Services
(`gateway/proximity`), is cached in `gateways.json` in the data folder
and refreshed at most once a day.

Winlink grants the access key on the condition that the endpoints are
queried sparingly, so the client enforces that itself: automatic
refresh only for a cache older than 24 h, exponential backoff after
failures, and a hard one-hour minimum that the refresh button cannot
get past either. A rejected key stops the automatic refresh instead of
retrying. Without a key, without a locator or offline, the built-in
starter list of Swiss ARDOP channels is used.

The key is not in this repository. It is read at build time from
`SKYWAVE_WEBSERVICE_KEY` or `~/.config/skywave/webservice-key` and
written masked into the app bundle; without one the build still
succeeds and falls back to the starter list. Masking keeps the key out
of a plain `strings` sweep — it is obfuscation, not protection.

## Radio

Skywave ships its own ARDOP modem: a macOS port of
[ardopcf](https://github.com/pflarue/ardop) (PortAudio/CoreAudio audio
backend, universal binary) lives in the app bundle and is started as a
managed child process during an exchange — no external modem program
needed. Settings → Funk switches between the integrated TNC and an
external one; PTT can be keyed via Icom CI-V CAT commands, RTS, rigctld
or VOX. See `Skywave/Vendor/ardopcf/` for the binary's version and
third-party license notes; the fork with the macOS backend is
[ardopcf-macos](https://github.com/christianmueller1970-oss/ardopcf-macos)
(branch `macos-port`).

Rig control uses a bundled `rigctld` from [Hamlib](https://hamlib.github.io)
(GPL, a separate program inside the app bundle). Version, source and build
script are described in `Skywave/Vendor/hamlib/README.md`.

Quitting Skywave while it keys the transmitter un-keys the rig first.
A force-quit or crash cannot do that: when Skywave keys through
rigctld, the rig may stay keyed until you un-key it by hand. Enable the
rig's transmit time-out as a backstop (IC-7300: MENU → SET → Function →
«Time-Out Timer (CI-V)»).

VARA remains supported as an external (Windows/Wine) modem.

## Building

Requires Xcode 16+ and [xcodegen](https://github.com/yonaskolb/XcodeGen).
WinlinkKit is expected as a sibling checkout at `../WinlinkKit`.

```bash
xcodegen generate
open Skywave.xcodeproj
```

Build settings live in `project.yml`, not in the Xcode project — the
project file is generated and gitignored.

The project is set up for the author's Apple developer team. To build it
yourself, change `DEVELOPMENT_TEAM` in `project.yml` to your own team (or
sign to run locally). A build without a Winlink web-service key works and
uses the built-in gateway list.

To update the bundled modem, rebuild it in a checkout of the ardopcf fork
next to this repository and copy it over:

```bash
cd ../ardopcf
scripts/build-portaudio.sh        # once, static universal libportaudio
scripts/build-macos-universal.sh  # → dist/ardopcf
cp dist/ardopcf ../Skywave/Skywave/Vendor/ardopcf/ardopcf
```

(The Xcode build re-signs the helper with hardened runtime and
sandbox-inherit entitlements; `scripts/release.sh` verifies that.)

## License

MIT, see `LICENSE`. Bundled third-party programs keep their own licenses:
`Skywave/Vendor/ardopcf/THIRD-PARTY-LICENSES-macos.md` and
`Skywave/Vendor/hamlib/README.md`.

---

*73 de HB9HJI*
