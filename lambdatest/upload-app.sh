#!/bin/bash
# Builds a debug .ipa and uploads it to LambdaTest App Storage for real-device testing.
#
# Usage:
#   ./lambdatest/upload-app.sh [path/to/SpektoWatch2.ipa]
#
# If no .ipa path is given the script builds one from source first.
#
# Required env vars:
#   LT_USERNAME    — LambdaTest username
#   LT_ACCESS_KEY  — LambdaTest access key
#
# On success, prints the app_url (lt://APP...) that you paste into Appium capabilities.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/SpektoWatch2.xcodeproj"
SCHEME="SpektoWatch2"
DERIVED_DATA="$REPO_ROOT/build/LambdaTest_DerivedData"
ARCHIVE_PATH="$DERIVED_DATA/SpektoWatch2.xcarchive"
IPA_PATH="${1:-$DERIVED_DATA/SpektoWatch2.ipa}"

for var in LT_USERNAME LT_ACCESS_KEY; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: $var is not set." >&2
        exit 1
    fi
done

# Build if no .ipa supplied
if [[ ! -f "$IPA_PATH" ]]; then
    echo "Building SpektoWatch2 for device..."
    mkdir -p "$DERIVED_DATA"

    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "generic/platform=iOS" \
        -archivePath "$ARCHIVE_PATH" \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        AD_HOC_CODE_SIGNING_ALLOWED=YES \
        | xcpretty 2>/dev/null || cat

    # Export .ipa from archive
    EXPORT_OPTIONS="$DERIVED_DATA/ExportOptions.plist"
    cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
PLIST

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$DERIVED_DATA/Export" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        | xcpretty 2>/dev/null || cat

    IPA_PATH=$(find "$DERIVED_DATA/Export" -name "*.ipa" | head -1)
    if [[ -z "$IPA_PATH" ]]; then
        echo "Error: no .ipa found after export." >&2
        exit 1
    fi
fi

echo "Uploading $(basename "$IPA_PATH") to LambdaTest..."

RESPONSE=$(curl -s -u "$LT_USERNAME:$LT_ACCESS_KEY" \
    -X POST "https://manual-api.lambdatest.com/app/upload/realDevice" \
    -F "appFile=@$IPA_PATH" \
    -F "name=SpektoWatch2")

APP_URL=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('app_url',''))" 2>/dev/null || echo "")

if [[ -z "$APP_URL" ]]; then
    echo "Upload failed. Response:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

echo ""
echo "Upload successful!"
echo "app_url: $APP_URL"
echo ""
echo "Use this in your Appium capabilities:"
echo '  "app": "'"$APP_URL"'"'
