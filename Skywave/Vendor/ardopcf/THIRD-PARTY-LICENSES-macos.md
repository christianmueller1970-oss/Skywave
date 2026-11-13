# Third-party licenses — ardopcf macOS binary

This file covers the components contained in the statically linked macOS
build of `ardopcf` (`scripts/build-macos-universal.sh`).  It is intended
for redistribution alongside the binary, e.g. inside an application
bundle such as Skywave.

## ardopcf

MIT License — Copyright (c) 2014-2024 Rick Muething (KN6KB),
John Wiseman (G8BPQ), Peter LaRue (KG4JJA).

See the `LICENSE` file of https://github.com/pflarue/ardop for the full
text.  The `lib/ws_server` (WebSocket server) and `lib/txt2c` components
are distributed as part of ardopcf under the same terms; `ws_server`
additionally contains socket-handling code adapted from "Beej's Guide to
Network Programming" by Brian "Beej Jorgensen" Hall, which its author
has placed in the public domain.

## Reed-Solomon encoder/decoder (lib/rockliff)

Copyright Simon Rockliff, University of Adelaide, 1989/1991.

> This program may be freely modified and/or given to whoever wants it.
> A condition of such distribution is that the author's contribution be
> acknowledged by his name being left in the comments heading the
> program, however no responsibility is accepted for any financial or
> other loss which may result from some unforeseen errors or
> malfunctioning of the program during use.
>
> — Simon Rockliff, 26th June 1991

## zf_log (lib/zf_log)

The MIT License (MIT) — Copyright (c) 2017 wonder-mice.
See `lib/zf_log/LICENSE` for the full text.

## PortAudio (statically linked)

PortAudio Portable Real-Time Audio Library —
Copyright (c) 1999-2006 Ross Bencina and Phil Burk.
Distributed under the PortAudio license (MIT-style); see
https://www.portaudio.com/license.html for the full text.

## Not included in the macOS build

The CM108 HID PTT support (`lib/rawhid`, containing code by PJRC.COM,
LLC, and `lib/hid`) is only compiled into the Linux and Windows builds
and is not part of the macOS binary.
