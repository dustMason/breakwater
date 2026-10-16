#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
cargo test --locked --target-dir Rust/target --manifest-path Rust/Cargo.toml
cargo build --locked --release --target-dir Rust/target --manifest-path Rust/Cargo.toml
case "$(uname -s)" in
  Darwin) set -- -framework Security -framework CoreFoundation ;;
  Linux) set -- -ldl -lpthread -lm -lrt -lutil ;;
  *) echo 'Unsupported test platform' >&2; exit 1 ;;
esac
clang++ -std=c++17 -O2 -I AudioCore -Wall -Wextra -Werror Tests/AudioCoreTests.cpp Rust/target/release/libbreakwater_audio.a "$@" -o build/audio-core-tests
./build/audio-core-tests
