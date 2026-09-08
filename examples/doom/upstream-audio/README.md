# The audio interface this example's module does not have yet

`doom.wasm` v0.1.0, the binary `examples/apps/scripts/doom.sh` pins, exposes
no audio interface: its ten imports carry the framebuffer, the clock, WAD
loading, save games and logging, and nothing tells a host that a sound
should be heard. Upstream lists audio as a wishlist item.

The patch here adds one, against `jacobenget/doom.wasm` at 31cc1af. It is
kept in this repository because the fork it belongs on could not be created
from the session that wrote it; it is not applied to anything here, and
nothing in this repository reads it.

## What it does

Doom needs no change for it. `i_sound.c` already looks for a
`DG_sound_module` / `DG_music_module` pair behind `FEATURE_SOUND`, and the
sound layers above are already compiled in; only the bottom layer, the one
that would touch an audio device, was missing. The patch supplies it as
thirteen `audio` imports and the two module structs that forward to them,
and fixes three things that kept `FEATURE_SOUND` from building at all.

Sample data crosses the boundary once per sound rather than once per play,
and music crosses as standard MIDI rather than Doom's own MUS encoding, so
a host needs neither a WAD reader nor a MUS parser. `ruby-gosu/audio.rb` is
the host half, written against this interface.

## Applying it

```sh
git clone https://github.com/jacobenget/doom.wasm
cd doom.wasm
git am ../0001-add-an-audio-interface-to-the-webassembly-module.patch
```

Building without the Docker image the Makefile reaches for needs a WASI SDK
and Binaryen on `PATH`, `SHELL=/bin/bash` (the recipes use `source`), a
Python 3.12 or newer virtualenv (`itertools.batched`), and a `build/DOOM1.WAD`
the Makefile's own download URL no longer serves.

```sh
make -j4 SHELL=/bin/bash build/doom.wasm CC=/path/to/wasi-sdk/bin/clang
```

Reverting the patch and building reproduces the released v0.1.0 binary
exactly (sha256 8edfe49a7583fd975199969302d8e9adcf8e714d0af72bf3e672f991fd810faa),
which is what makes the diff the only difference.
