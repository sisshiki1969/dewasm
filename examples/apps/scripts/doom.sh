#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh

# doom: jacobenget/doom.wasm v0.1.0 (DOOM shareware, WAD embedded) plus the audio interface that release does not have.
# Shared between the examples/doom demo frontends and the deterministic framebuffer-snapshot test, so it lives in the apps cache like every other fixture, checksum-pinned here, unlike the old examples/doom/fetch.sh which downloaded it unverified.
# The pin is a fork's branch rather than a release because upstream has not taken the audio change yet and so has nothing to release; reverting that change and rebuilding reproduces the v0.1.0 release binary exactly (sha256 8edfe49a7583fd975199969302d8e9adcf8e714d0af72bf3e672f991fd810faa), which is what makes it one commit's difference and not a different DOOM.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

fetch_app doom \
  "https://raw.githubusercontent.com/sisshiki1969/doom.wasm/47a5670d0c3a9c89d20eac1eeb3610957107d57f/doom.wasm" \
  af767e8e69ff91758457001cf1b6e652efc52e0f3cda1e4a90e4652a01d86f46
