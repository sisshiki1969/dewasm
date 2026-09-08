# Decision 91: Extend the Guest When the Interface, Not the Frontend, Is What Is Missing

Status: **Accepted, 2026-09-08.**
`examples/doom` pins upstream doom.wasm v0.1.0 plus [one commit](https://github.com/sisshiki1969/doom.wasm/tree/sound) adding thirteen `audio` imports, and `ruby-gosu/audio.rb` plays them; the other six frontends answer those imports silently.
This revises [decision 50](50-doom-example-shape.md)'s criterion, which forbade rebuilding the guest at all.

## Context

Decision 50 recorded "No sound: the module exposes no audio interface" as a known cost, and its criterion made that cost permanent: *a frontend may only differ in host-side code, never by rebuilding or patching the guest.*

The criterion was written against a real failure mode, per-language guest builds, where each frontend would demonstrate a different binary and the one-artifact claim would collapse.
It reads as a ban on touching the guest at all, which is stronger than what that failure mode requires.

Sound is the case that separates the two readings.
No host layer can produce it: the module has no import a host could implement, and DOOM's own request to play a sound reaches a `sound_module_t` that the build leaves null.
The data is all present (the WAD holds 55 `DS*` lumps and 13 `D_*` songs, and `i_sound.c` / `s_sound.c` / `sounds.c` are compiled in); only the bottom layer, the one that would touch an audio device, is absent.
Upstream lists audio as a wishlist item and has released nothing since v0.1.0.

## Decision

**A frontend may not rebuild the guest to suit itself; a missing *interface* is fixed once, in the guest, for every frontend.**

The discriminating question is who the change serves.
A guest rebuild that gives one frontend what the others do not have breaks the one-artifact claim and stays forbidden.
A guest rebuild that adds an import surface every frontend can implement does not: it is the same artifact for all of them, and it is what the import surface being the porting seam *means* when the seam has a hole in it.

Three conditions keep that from becoming a licence to fork freely:

- **The guest's own extension point is used, or there is none.**
  Here doomgeneric already defines `DG_sound_module` / `DG_music_module` behind `FEATURE_SOUND`; the commit fills them and leaves DOOM untouched.
- **Reverting the change reproduces the pinned upstream release byte for byte.**
  That is what makes the pin auditable as "the release plus this diff" rather than a different program, and it is checked: reverting reproduces v0.1.0's `8edfe49a…`.
- **The change is offered upstream.**
  A fork branch is where it waits, not where it lives.

The interface itself follows the seam's existing shape: integers and pointers, no host runtime assumed.
Sample data crosses once per sound rather than once per play (`registerSound` then `startSound` by id), and music crosses as MIDI, the module converting DOOM's MUS encoding with the `mus2mid` already in its tree, so that no frontend needs a WAD reader or a MUS parser.

## Rejected alternatives

- **Read DOOM's sound state out of linear memory.**
  Host-side only, so it satisfies decision 50's criterion literally, and it works: `S_sfx[]` is locatable from the sfx name strings at a 48-byte stride, and `channels[]` from the pointers into it.
  Rejected because it bypasses the import surface entirely, which is the thing this example exists to show, and because it is version-locked to one binary in a way an import surface is not: a checksum bump breaks it silently.
- **Music only, from the WAD in memory.**
  Needs no knowledge of DOOM's layout (the WAD is self-describing, and the host may supply one through `loading.readWads` anyway) and no upstream change.
  Rejected because nothing reports a level change, so the music could not follow the game, and because it leaves the effects, which is most of what "DOOM has sound" means.
- **Switch to a DOOM wasm build that already has audio.**
  [cloudflare/doom-wasm](https://github.com/cloudflare/doom-wasm), [VanIseghemThomas/wasmDOOM](https://github.com/VanIseghemThomas/wasmDOOM) and [lazarv/wasm-doom](https://github.com/lazarv/wasm-doom) all have sound.
  All are Emscripten builds bound to a JavaScript runtime, which is the per-language-glue shape decision 50 rejected; the builds that avoid it ([diekmann/wasm-fizzbuzz](https://github.com/diekmann/wasm-fizzbuzz/tree/main/doom)) have no sound.
  No existing build pairs a small hand-written import surface with audio.
- **Wait for upstream.**
  The change is offered there, but v0.1.0 is two years old and audio has been on the wishlist throughout.

## Consequences

- Positive: the example gains the one capability its README had recorded as permanently missing, and gains it in the shape the example is about: thirteen imports, implementable in any of the six languages.
  The framebuffer snapshot ([decision 53](53-doom-frame-snapshot.md)) is byte-identical before and after, which is the evidence that audio changed no pixel.
- Negative: the pin is a fork branch rather than a release, because upstream has nothing to release yet, and `raw.githubusercontent.com` rather than a release asset because the session that built it could not create one.
  Both move as soon as upstream takes the change.
  A wasm import cannot be omitted, so six frontends carry thirteen imports they answer with nothing; that is spelled silence, not dead code, and it is what a machine with no sound device looked like.
- Carry-over: gosu decodes audio with SDL_sound, whose decoder set has no MIDI in it, so the frontend that motivated the interface plays the effects through gosu and the music through SDL2_mixer, the library Doom's own SDL backend plays these same files with.
  That is the frontend's business, not the interface's: what crosses the seam is still a MIDI file.
- Carry-over: enabling `FEATURE_SOUND` for the first time surfaced three latent faults in doomgeneric, all invisible while it was never defined: `DG_sound_module` declared as a pointer but defined and used as a value; `FEATURE_SOUND` doing double duty as "SDL's headers are available", pulling `<SDL_endian.h>` into endianness handling that has nothing to do with sound; and `I_PrecacheSounds` running as `S_Init`'s first statement, before the loop that sets each `lumpnum` to -1, so every sound resolves to lump 0 (`PLAYPAL`).
  A dormant extension point is not a tested one.
