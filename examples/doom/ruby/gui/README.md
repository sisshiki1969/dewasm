# DOOM (Ruby, gosu window)

An interactive DOOM frontend that renders into a window with [gosu](https://www.libgosu.org/), the SDL2-backed 2D game library for Ruby.
The parent [`../`](../) frontend draws the same game into a terminal; this one takes a real window.

Both frontends share one generated library: `../build.sh` fetches jacobenget/doom.wasm (checksum-pinned into the shared apps cache) and converts it to Ruby with dewasm (`../doom_gen.rb`, ~11MB, gitignored, regenerated on every build).
`main.rb` implements the module's host imports (console logging, save-game I/O, the game clock, and frame delivery) plus the gosu window, its renderer and its keyboard input.
`audio.rb` implements the thirteen audio imports on gosu, and `midi_song.rb` plays the music gosu cannot decode, both described under [Sound](#sound).

## Requirements

gosu, and the ffi that `midi_song.rb` needs, are installed by `run.sh` with bundler, into the gitignored `vendor/bundle` of this directory, at the version pinned by `Gemfile.lock`.
Nothing is installed globally, and the parent terminal frontend stays stdlib-only.

The gem builds a native extension against SDL2, so its development headers have to be present:

| Platform | Install |
| --- | --- |
| Debian/Ubuntu | `sudo apt install libsdl2-dev` |
| Fedora | `sudo dnf install SDL2-devel` |
| macOS | `brew install sdl2` |

On macOS, Homebrew's `sdl2` currently resolves to sdl2-compat, whose `sdl2-config` does not support the `--static-libs` flag gosu's build uses; the extension then builds without its SDL2 and AppKit link line and fails at require time with a missing-symbol error.
Until gosu handles sdl2-compat, install against a real SDL2 (`brew install sdl2 --formula` with a pre-compat bottle, or MacPorts), or wrap `sdl2-config` so `--static-libs` answers with the `--libs` output.

Sound effects need nothing beyond that.
Music needs SDL2_mixer and a soundfont, for the reason under [Sound](#sound):

| Platform | Install | Soundfont |
| --- | --- | --- |
| Debian/Ubuntu | `sudo apt install libsdl2-mixer-2.0-0 fluid-soundfont-gm` | found at `/usr/share/sounds/sf2/default-GM.sf2` |
| macOS | `brew install sdl2_mixer` | `export SDL_SOUNDFONTS=/path/to/some.sf2` |

SDL2_mixer synthesises MIDI with fluidsynth, which needs a soundfont.
On Linux it reads `/usr/share/sounds/sf2/default-GM.sf2` without being told; on macOS there is no such default, so `SDL_SOUNDFONTS` has to name one.
Without either the game runs with its effects and no music, and says so once.

## Why a window is affordable here

The terminal frontend exists because the Ruby backend only manages ~15 ticks/sec under YJIT, far below what a GUI usually needs, while a terminal has orders of magnitude fewer cells to redraw than a window has pixels.
A window costs no more than a terminal here because the per-frame work does not scale with the window: the frame is uploaded once as a 320x200 texture and the GPU does the scaling, so `--scale 6` costs exactly what `--scale 1` costs.

The framebuffer the module hands over is 640x400, but DOOM renders at 320x200 and upscales by exactly 2 (its own startup log reads `I_InitGraphics: Auto-scaling factor: 2`).
Halving it back is therefore lossless, and leaves 64000 pixels per frame to convert instead of 256000.
`FrameConverter` verifies that on the first frame rather than trusting it, and falls back to full resolution if a future build of the module ever stops holding it.

What the window buys over the terminal is real key releases.
Terminals report presses only, so the terminal frontend has to synthesize a release after a hold window, and cannot deliver Ctrl as a plain key at all.
Here Ctrl (fire) and Shift (run) work as they do in DOOM.

## Run

```sh
./run.sh
```

builds and opens a window.
The window is resizable: the frame keeps its 8:5 aspect ratio and is centered, with black bars on whichever axis runs out first.

| Option | Effect |
| --- | --- |
| `--scale N` | Window size as a multiple of 320x200, 1 to 8 (default 3, so 960x600). |
| `--fullscreen` | Start fullscreen. |
| `--smooth` | Scale the frame with interpolation instead of nearest-neighbor, saving ~10ms per frame. |
| `--smoke` | Headless self-check, described below. |

`./run.sh --smoke` needs no display: it inits the game, ticks it 60 times with no window, reports the tick rate and the per-frame conversion cost, sanity-checks the last frame, writes it to `screenshot.png`, and exits non-zero on failure.
gosu encodes PNGs without a graphics context, so unlike the terminal frontend (which falls back to binary PPM for want of a stdlib PNG writer) this writes a real PNG.

## Rendering

Handing a frame to gosu takes two per-pixel transformations, and they are the only part of this frontend where a straightforward Ruby loop would cost more than the wasm tick itself.
The module stores pixels as B,G,R,A while gosu wants R,G,B,A, and the module's alpha byte is always 0 where gosu needs 0xff.

Two facts about DOOM's renderer keep that down to a few hundred Ruby-level operations per frame rather than 64000.
It is paletted (VGA Mode 13h, at most 256 colors per palette and a handful of palettes over a session), so each distinct 32-bit source word is swizzled once and memoized; a real frame holds around 175 of them.
Its 640x400 output is an exact 2x upscale, so each row is read with a single `unpack("Vx4" * 320)`, where `V` takes a 32-bit pixel and `x4` skips the duplicated neighbor.
That leaves one `unpack`, one memoized `map!` and one `pack` per row, all at C level except the hash lookups.

Uploading the result is one `Gosu::Image.from_blob` per frame.
gosu interpolates an image scaled past its native size unless its texture was created with `retro: true`, which `Image.from_blob` has no parameter for, so the default path blits the frame into a persistent nearest-neighbor render target instead.
That is what `--smooth` turns off, trading DOOM's crisp pixels for the ~10ms.

Measured on an x86-64 Linux container under Ruby 3.3.6 **without** YJIT (that build of Ruby has no YJIT support), at the default `--scale 3`:

| Step | Cost per frame |
| --- | --- |
| Framebuffer conversion (640x400 BGRA to 320x200 RGBA) | 9.9ms |
| `Gosu::Image.from_blob` | 2.0ms |
| Nearest-neighbor blit (skipped by `--smooth`) | 10.0ms |
| One `tickGame` | 226ms |

The wasm tick dominates by an order of magnitude, which is the point: rendering is not what makes this frontend slow, and YJIT (which `run.sh` always passes, and which `main.rb` warns about on stderr if it ends up missing) is what moves the tick figure.
The terminal frontend measures the same Ruby backend at 15.9 ticks/sec with YJIT on an Apple Silicon laptop.

## Controls

| Key | Action |
| --- | --- |
| Arrow keys | Move / turn |
| Ctrl | Fire |
| Space | Use (open doors, flip switches) |
| Shift | Run |
| , / . | Strafe left / right |
| Tab | Automap |
| Enter | Menu confirm |
| Escape | Menu / pause |
| Backspace | Menu back |
| 0-9 | Weapon select / text entry |
| Letters | Text entry, `y` / `n` prompts |
| F1 | Show or hide the on-screen status bar |
| F10 | Quit |

gosu closes a window on Escape unless the frontend overrides its `button_down`, which this one does: Escape belongs to DOOM's menu, and quitting is F10 or the window's close button.

Save games are written to `.savegame/` (gitignored) relative to wherever the script runs.

## Sound

The module hands over each sound as a DMX lump (an 8-byte header and unsigned 8-bit mono samples) and each song as standard MIDI, having converted it from DOOM's own MUS encoding.
`audio.rb` wraps a lump in a 44-byte WAV header, which costs one string concatenation per distinct sound, and writes both to files because gosu loads audio from paths rather than from memory.

Music does not go to `Gosu::Song`, though it is offered there first.
gosu decodes audio with SDL_sound, whose decoders are WAV, AIFF, VOC, AU, FLAC, MP3, Ogg Vorbis, Shorten and tracker modules: MIDI is not among them, so a released gosu answers `Could not parse audio file ...: Sound format unsupported` for every song, whatever the machine has installed.
`midi_song.rb` therefore binds the eleven SDL2_mixer entry points that music needs and presents them as `Gosu::Song`'s interface, so the rest of `audio.rb` does not know which one it holds.
SDL2_mixer is what DOOM's own SDL backend plays these same files with, and it synthesises MIDI through fluidsynth or timidity.

Offering gosu the file first is not a formality: monoruby ships a gosu whose audio *is* SDL2_mixer, and there `Gosu::Song` takes the MIDI and no second output device is opened.
