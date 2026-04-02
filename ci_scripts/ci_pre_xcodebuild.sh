#!/bin/sh
set -e

# Download Metal Toolchain if not present.
# Required for xcodebuild analyze and Metal shader compilation on Xcode Cloud agents.
if ! xcrun --find metal &>/dev/null; then
    echo "Metal Toolchain not found. Downloading..."
    xcodebuild -downloadComponent MetalToolchain
else
    echo "Metal Toolchain already available."
fi
