#!/bin/sh
# ci_post_xcodebuild.sh — Xcode Cloud post-build hook.
#
# Extracts PNG screenshots from the xcresult bundle and places them in a
# "Screenshots" folder that Xcode Cloud surfaces as a downloadable build
# artifact.
#
# Environment variables provided by Xcode Cloud:
#   CI_RESULT_BUNDLE_PATH   — path to the .xcresult bundle written by the run
#   CI_DERIVED_DATA_PATH    — derived data root (fallback xcresult search)
#   CI_WORKSPACE            — root of the checked-out repository
#
# Reference: developer.apple.com/documentation/xcode/environment-variable-reference

set -eu

log() { echo "[ci_post_xcodebuild] $*"; }

# Locate the xcresult bundle.
XCRESULT=""
if [ -n "${CI_RESULT_BUNDLE_PATH:-}" ] && [ -e "$CI_RESULT_BUNDLE_PATH" ]; then
    XCRESULT="$CI_RESULT_BUNDLE_PATH"
elif [ -n "${CI_DERIVED_DATA_PATH:-}" ]; then
    XCRESULT="$(find "$CI_DERIVED_DATA_PATH" -maxdepth 5 -name "*.xcresult" -type d 2>/dev/null | head -n 1)"
fi

if [ -z "$XCRESULT" ] || [ ! -e "$XCRESULT" ]; then
    log "⚠️  No .xcresult bundle found — skipping screenshot extraction."
    exit 0
fi
log "Found xcresult: $XCRESULT"

# Output directory.  Xcode Cloud exposes files placed under CI_RESULT_BUNDLE_PATH
# (or a sibling "Artifacts" folder) as downloadable artifacts.
OUTPUT_DIR="${CI_RESULT_BUNDLE_PATH%/*}/Screenshots"
mkdir -p "$OUTPUT_DIR"

REPO_ROOT="${CI_WORKSPACE:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
SCRIPT="$REPO_ROOT/agent/scripts/capture-screenshots.py"

if [ ! -f "$SCRIPT" ]; then
    log "⚠️  capture-screenshots.py not found at $SCRIPT — skipping."
    exit 0
fi

log "Extracting screenshots to $OUTPUT_DIR …"
python3 "$SCRIPT" --xcresult "$XCRESULT" --output "$OUTPUT_DIR" || true

PNG_COUNT="$(find "$OUTPUT_DIR" -name "*.png" | wc -l | tr -d ' ')"
log "Extracted $PNG_COUNT PNG(s) to $OUTPUT_DIR"

if [ "$PNG_COUNT" -eq 0 ]; then
    # Emit a warning that will be visible in the Xcode Cloud build log.
    # This catches xcresulttool format drift before it silently regresses.
    echo "##[warning] Zero screenshots extracted from xcresult — check xcresulttool format or UITest target configuration."
fi
