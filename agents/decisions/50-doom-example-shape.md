# Decision 50: DOOM Demo (One Wasm Binary, Per-Language Native Frontends)

Status: **Accepted, 2026-07-30.**
`examples/doom` runs the unmodified [jacobenget/doom.wasm](https://github.com/jacobenget/doom.wasm) v0.1.0 release binary through `--mode library`, with an ebiten frontend for the Go backend and a Swing frontend for the Java backend; both pass a headless smoke that renders a real frame well above DOOM's native 35Hz tic rate.
Extended the same day with Ruby and Python frontends that render into the terminal (ANSI truecolor half-blocks, stdlib only), the same criterion applied at slower tick rates, where a pixel window would be pointless but a diffed terminal frame costs under 1ms.
Extended again with `ruby-gosu/`, a windowed Ruby frontend on gosu, and with it the first second frontend for a backend that already had one.

## Context

The Rails demo ([decision 45](45-rails-sqlite3-shim-example.md)) shows a converted *reactor library* driven through an existing API.
It has no counterpart for interactive programs where the host owns the event loop, the clock, and the screen: the case where `--mode library`'s import surface, not WASI, is the platform boundary.
doom.wasm is the sharpest available specimen: ten imported functions (framebuffer hand-off, monotonic clock, WAD loading, save games, logging), four exports plus memory, no WASI, and the shareware WAD embedded so the demo needs zero game assets.

## Decision

Convert **one upstream release binary, unmodified, once per language**, and implement its ten-function import surface natively in each frontend: Go with ebiten, Java with Swing.
Criterion, reusable for future interactive demos: *the wasm module is the portable artifact and the import surface is the porting seam; a frontend may only differ in host-side code, never by rebuilding or patching the guest.*
Two consequences of the criterion: frontends stay dependency-light in each language's idiom (Swing is plain JDK; ebiten is the one Go dependency), and every frontend carries a headless `-smoke` mode that ticks the game and PNG-dumps the framebuffer, so the semantics-bearing path (memory layout, pixel format, clock pacing) is verified without a window.
The example is documentation-level: fetched and built by its own scripts, outside the `cargo test` speed categories ([decision 48](48-slow-test-speeds.md)).

## Rejected alternatives

- **Standalone mode over a WASI port of DOOM.**
  Inverts the demo: WASI has no display/input surface, so the interesting part would live in a bespoke shim, and nothing would exercise `--mode library`'s host-import path, the thing this example exists to show.
- **Per-language guest builds (e.g. Emscripten JS glue, TinyGo-side ports).**
  Breaks the one-artifact claim that makes the demo persuasive; every frontend would demonstrate a different binary.
- **A uniform SDL binding layer in every language.**
  One rendering stack to learn, but it imports a C dependency into languages whose selling point here is "plain JDK" / "one idiomatic game library", and SDL bindings for Java are effectively abandonware.
  Rejected for Java specifically against JavaFX (external module since JDK 11) and libGDX (build-system weight disproportionate to a framebuffer blit).

## Consequences

- Positive: first interactive, real-time proof of the Go and Java backends (measured headless: ~70 and ~55 ticks/sec against DOOM's 35Hz target); a reference embedding for the library-mode import surface in both languages, complementing [decision 45](45-rails-sqlite3-shim-example.md)'s export-driven shape.
- Negative: the example is unguarded by CI (network fetch, GUI); upstream doom.wasm is pinned to v0.1.0 and interface drift would surface only when someone reruns `build.sh`.
  No sound: the module exposes no audio interface.
  [Decision 53](53-doom-frame-snapshot.md) later closes part of this gap with a deterministic framebuffer snapshot (ultra-slow execution, a CI-side conversion smoke).
- Carry-over: the Ruby (~15 ticks/sec under YJIT) and Python (~1.3) frontends confirmed the criterion: each was a new host layer only, with the guest untouched.
  So did `ruby-gosu/`, which additionally shows the criterion does not cap a backend at one frontend: the title's "per-language" describes how the demo grew, not a limit on it, and two frontends for one backend cost nothing beyond their own host code.
  It also revises the reading that a slow backend implies a terminal.
  What made a window look unaffordable for Ruby was per-pixel cost against a ~15 ticks/sec budget, and the module's 640x400 framebuffer is an exact 2x upscale of DOOM's native 320x200 (`I_InitGraphics: Auto-scaling factor: 2`), so halving it back is lossless and leaves a quarter of the pixels to convert; the frame is then uploaded once as a 320x200 texture and scaled by the GPU, making the render cost independent of window size.
  The window also restores real key releases, which no terminal can deliver, so Ctrl (fire) and Shift (run) work as in DOOM instead of being synthesized or dropped.
  The terminal renderer doubles as the frontend shape for any backend too slow for a window, including Bash, which after [decision 51](51-bash-assoc-memory.md)/[decision 52](52-bash-inline-memops.md) boots in ~2 minutes and renders a frame every ~34 seconds in `bash/`.
