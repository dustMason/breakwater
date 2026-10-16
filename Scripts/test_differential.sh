#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
cargo build --locked --release --target-dir Rust/target --manifest-path Rust/Cargo.toml
case "$(uname -s)" in
  Darwin) set -- -framework Security -framework CoreFoundation ;;
  Linux) set -- -ldl -lpthread -lm -lrt -lutil ;;
  *) echo 'Unsupported test platform' >&2; exit 1 ;;
esac
clang++ -std=c++17 -O2 -I AudioCore -include Tests/Reference/Rename.h -fsanitize=address,undefined -c Tests/Reference/LegacyAudio.cpp -o build/legacy-audio.o
clang++ -std=c++17 -O2 -I AudioCore -Wall -Wextra -Werror -fsanitize=address,undefined Tests/DifferentialTests.cpp build/legacy-audio.o Rust/target/release/libbreakwater_audio.a "$@" -o build/audio-differential-tests
./build/audio-differential-tests
