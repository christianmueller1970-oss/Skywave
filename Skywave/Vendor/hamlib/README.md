# Bundled rigctld (Hamlib)

Skywave ships `rigctld`, the rig control daemon of the [Hamlib](https://hamlib.github.io)
project, as a separate helper program inside the app bundle. Skywave starts it as a child
process and talks to it over a local TCP port; it is not linked into Skywave.

| | |
|---|---|
| Version | Hamlib 4.7.1 |
| Source commit | `d042479` (2026-04-15) |
| Source code | https://github.com/Hamlib/Hamlib/tree/4.7.1 |
| Binary | universal (x86_64 + arm64), static, without libusb |
| Built with | [`scripts/build-hamlib.sh`](../../../scripts/build-hamlib.sh) in this repository |

The binary is built from the unmodified Hamlib sources at that tag.

## Licence

`rigctld` is licensed under the GNU General Public License, version 2 or later
(`HAMLIB-COPYING`); the Hamlib library it is built from is licensed under the GNU Lesser
General Public License, version 2.1 or later (`HAMLIB-COPYING.LIB`). Both texts are in this
folder and are copied into the app bundle. Skywave itself is MIT-licensed; the two programs
are distributed side by side.

To rebuild the binary yourself, run `scripts/build-hamlib.sh` (needs autoconf, automake,
libtool and pkg-config, e.g. from Homebrew). It clones Hamlib at the pinned tag, builds both
architectures and writes `Skywave/Vendor/hamlib/rigctld`.
