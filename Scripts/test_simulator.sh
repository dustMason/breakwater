#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -ne 1 ]; then
  echo 'Usage: Scripts/test_simulator.sh <iPad Simulator UDID>' >&2
  echo 'List available devices with: xcrun simctl list devices available' >&2
  exit 2
fi
xcodebuild -project Breakwater.xcodeproj -scheme Breakwater -configuration Debug \
  -destination "platform=iOS Simulator,id=$1" -derivedDataPath build/Xcode \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
