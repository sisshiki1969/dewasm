#!/usr/bin/env bash
# Regenerate the dewasm-generated DOOM library and check the frontend. doom_gen.rb is ~10MB of generated code and is gitignored, so this step has to run before main.rb can require it from a clean checkout.
# There's no compile step for Ruby; `ruby -c` stands in for one.
set -euo pipefail
cd "$(dirname "$0")"

repo_root="$(cd ../../.. && pwd)"

../../apps/scripts/doom.sh

(
  cd "$repo_root"
  cargo run -q -p dewasm -- \
    examples/apps/cache/doom.wasm \
    --target ruby --mode library --module-name Doom \
    -o examples/doom/ruby-gosu/doom_gen.rb
)

ruby -c main.rb

# gosu is the only thing this frontend needs beyond the stdlib, and it builds a native extension against system SDL2.
# Reporting that here, with the install command, beats a bare LoadError out of main.rb.
if ! ruby -e 'require "gosu"' >/dev/null 2>&1; then
  cat >&2 <<'MSG'
build: the gosu gem is not installed. Install it with:

  gem install gosu

It compiles against SDL2 development headers:
  Debian/Ubuntu  sudo apt install libsdl2-dev
  Fedora         sudo dnf install SDL2-devel
  macOS          brew install sdl2
MSG
  exit 1
fi

echo "build complete: doom_gen.rb regenerated"
