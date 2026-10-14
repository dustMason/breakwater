#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
clang++ -std=c++17 -O2 -I AudioCore -Wall -Wextra -Werror -fsanitize=address,undefined AudioCore/BreakwaterAudio.cpp Tests/AudioCoreTests.cpp -o build/audio-core-tests
./build/audio-core-tests
