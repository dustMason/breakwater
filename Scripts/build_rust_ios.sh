#!/bin/sh
set -eu
# Xcode GUI builds do not inherit the shell's rustup PATH.
PATH="$HOME/.cargo/bin:$PATH"
export PATH
if ! command -v cargo >/dev/null 2>&1; then
  echo 'Rust is required. Install rustup and the iOS targets described in INSTALL.md.' >&2
  exit 1
fi
export CARGO_TARGET_DIR="$DERIVED_FILE_DIR/breakwater-rust"
set --
for arch in $ARCHS; do
  case "$PLATFORM_NAME:$arch" in
    iphoneos:arm64) target=aarch64-apple-ios ;;
    iphonesimulator:arm64) target=aarch64-apple-ios-sim ;;
    iphonesimulator:x86_64) target=x86_64-apple-ios ;;
    *) echo "Unsupported iOS architecture: $PLATFORM_NAME $arch" >&2; exit 1 ;;
  esac
  cargo build --locked --release --manifest-path "$SRCROOT/Rust/Cargo.toml" --target "$target"
  set -- "$@" "$CARGO_TARGET_DIR/$target/release/libbreakwater_audio.a"
done
if [ "$#" -eq 0 ]; then echo 'No architectures to build' >&2; exit 1; fi
mkdir -p "$BUILT_PRODUCTS_DIR"
if [ "$#" -eq 1 ]; then cp "$1" "$BUILT_PRODUCTS_DIR/libbreakwater_audio.a"
else xcrun lipo -create "$@" -output "$BUILT_PRODUCTS_DIR/libbreakwater_audio.a"; fi
