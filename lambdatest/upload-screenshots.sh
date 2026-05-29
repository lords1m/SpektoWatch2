#!/bin/bash
# Uploads PNG screenshots to LambdaTest SmartUI for visual regression comparison.
#
# Usage:
#   ./lambdatest/upload-screenshots.sh <screenshots-dir> [build-name]
#
# Required env vars:
#   LT_USERNAME      — LambdaTest username
#   LT_ACCESS_KEY    — LambdaTest access key
#   LT_PROJECT_TOKEN — SmartUI project token (from app.lambdatest.com/smart-visual-testing)
#
# Optional env vars:
#   LT_BUILD_NAME    — overrides the build-name argument (useful in CI)

set -euo pipefail

SCREENSHOTS_DIR="${1:-}"
BUILD_NAME="${LT_BUILD_NAME:-${2:-SpektoWatch2-$(date +%Y%m%d-%H%M%S)}}"

# Validate arguments
if [[ -z "$SCREENSHOTS_DIR" ]]; then
    echo "Usage: $0 <screenshots-dir> [build-name]" >&2
    exit 1
fi

if [[ ! -d "$SCREENSHOTS_DIR" ]]; then
    echo "Error: screenshots directory not found: $SCREENSHOTS_DIR" >&2
    exit 1
fi

PNG_COUNT=$(find "$SCREENSHOTS_DIR" -name "*.png" | wc -l | tr -d ' ')
if [[ "$PNG_COUNT" -eq 0 ]]; then
    echo "Warning: no PNG files found in $SCREENSHOTS_DIR — skipping SmartUI upload."
    exit 0
fi

# Validate credentials
for var in LT_USERNAME LT_ACCESS_KEY LT_PROJECT_TOKEN; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: $var is not set. Export it before running this script." >&2
        exit 1
    fi
done

echo "Uploading $PNG_COUNT screenshot(s) to LambdaTest SmartUI..."
echo "  Build: $BUILD_NAME"
echo "  Dir:   $SCREENSHOTS_DIR"

export PROJECT_TOKEN="$LT_PROJECT_TOKEN"

npx --yes @lambdatest/smartui-cli@latest upload "$SCREENSHOTS_DIR" \
    --buildName "$BUILD_NAME" \
    --config "$(dirname "$0")/../smartui.json"

echo "SmartUI upload complete."
echo "View results: https://app.lambdatest.com/smart-visual-testing"
