# NES (Ruby, gosu window)

An interactive NES frontend that renders into a window with [gosu](https://www.libgosu.org/), the SDL2-backed 2D game library for Ruby.
The parent [`../`](../) frontend draws the same emulator into a terminal; this one takes a real window.
It is the NES counterpart of [`../../../doom/ruby/gui`](../../../doom/ruby/gui), in the same shape: the generated library is shared with the terminal frontend (`../build.sh` regenerates `../nes_gen.rb`, which both require), and gosu is scoped to this directory with bundler.

## Requirements

gosu is installed by `run.sh` with bundler, into the gitignored `vendor/bundle` of this directory, at the version pinned by `Gemfile.lock`.
Nothing is installed globally, and the parent terminal frontend stays stdlib-only.
The gem builds a native extension against SDL2; the development-header packages and the current macOS sdl2-compat caveat are in the [DOOM gui frontend's README](../../../doom/ruby/gui/README.md#requirements).

## Run

```sh
./run.sh
./run.sh path/to/game.nes   # any ROM agnes's mappers cover
```

builds and opens a window.
The window is resizable: the frame keeps its ratio and is centered, with black bars on whichever axis runs out first.

| Option | Effect |
| --- | --- |
| `--scale N` | Window size as a multiple of 256x240, 1 to 8 (default 3, so 768x720). |
| `--fullscreen` | Start fullscreen. |
| `--smooth` | Scale the frame with interpolation instead of nearest-neighbor. |
| `--smoke` | Headless self-check, described below. |

`./run.sh --smoke` needs no display: it inits the emulator, ticks it 300 times with no input, reports the tick rate and the per-frame conversion cost, sanity-checks the last frame, writes it to `screenshot.png`, and exits non-zero on failure.

## Rendering

The module hands over agnes's own frame representation: one palette *index* per pixel at `screenOffset()`, against the fixed 64-entry palette at `paletteOffset()`.
That keeps the per-pixel conversion to one Array lookup: each of the 256 possible index bytes maps to a precomputed 32-bit RGBA word (the module's `& 0x3f` mask folded into the table), so a frame is one `unpack`, one `map!` over the table and one `pack`, all at C level except the lookups.
The 256x240 result is uploaded once per frame and the GPU does the scaling, so the render cost does not grow with the window; nearest-neighbor versus interpolated scaling works exactly as in the DOOM gui frontend (`retro: true` render target, `--smooth` to opt out).

Pacing is gosu's own 60Hz update interval (the NTSC NES's real rate is ~60.0988Hz: close enough that no calibration is needed).
When the interpreter cannot sustain 60 ticks/sec, updates simply run late, which is the same fastest-sustainable-rate behavior the terminal frontend implements by hand.

## Controls

Where the terminal frontend has to synthesize key releases after a hold window, gosu reports real `button_down`/`button_up` events, and the held-button bitmask `setInput` wants every tick falls out of them directly.

| Key | Action |
| --- | --- |
| Arrow keys | D-pad |
| x | A |
| z | B |
| Enter | Start |
| Space | Select |
| F1 | Show or hide the on-screen status bar |
| q / Escape | Quit |

The bundled ROM is [Alter Ego](https://forums.nesdev.org/viewtopic.php?t=7999) by Shiru, released into the public domain.
