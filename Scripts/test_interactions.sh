#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 -module-cache-path build/module-cache App/Catalog.swift App/PadGesture.swift App/MIDIInput.swift Tests/InteractionTests.swift -o build/interaction-tests
./build/interaction-tests
python3 Tests/ClockAndCatalogTests.py
