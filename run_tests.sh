#!/bin/bash

# SpektoWatch Test Runner Script
# Führt alle Unit- und UI-Tests aus basierend auf dem Testkonzept

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="SpektoWatch2"
SCHEME_IOS="SpektoWatch2"
DESTINATION_IOS="platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2"

echo "=========================================="
echo "SpektoWatch Test Runner"
echo "=========================================="
echo ""
echo "Projekt: $PROJECT_DIR"
echo "Datum: $(date)"
echo ""

# Funktion zum Ausführen von Tests
run_tests() {
    local test_type=$1
    local test_target=$2

    echo "------------------------------------------"
    echo "Running: $test_type"
    echo "------------------------------------------"

    xcodebuild test \
        -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME_IOS" \
        -destination "$DESTINATION_IOS" \
        -only-testing:"$test_target" \
        -resultBundlePath "$PROJECT_DIR/TestResults/$test_type.xcresult" \
        2>&1 | xcpretty

    if [ $? -eq 0 ]; then
        echo "✅ $test_type PASSED"
    else
        echo "❌ $test_type FAILED"
        return 1
    fi
}

# Erstelle Ergebnis-Verzeichnis
mkdir -p "$PROJECT_DIR/TestResults"

# Unit Tests
echo ""
echo "=========================================="
echo "UNIT TESTS"
echo "=========================================="

echo ""
echo "1. FFTProcessor Tests (TEST-IE-010, TEST-IE-011)"
run_tests "FFTProcessorTests" "SpektoWatch2Tests/FFTProcessorTests" || true

echo ""
echo "2. FrequencyWeighting Tests (TEST-IE-020, TEST-IE-021, TEST-IE-022)"
run_tests "FrequencyWeightingTests" "SpektoWatch2Tests/FrequencyWeightingTests" || true

echo ""
echo "3. WatchConnectivity Tests (TEST-INT-002, TEST-INT-003)"
run_tests "WatchConnectivityTests" "SpektoWatch2Tests/WatchConnectivityTests" || true

echo ""
echo "4. AudioEngine Tests (TEST-INT-010)"
run_tests "AudioEngineTests" "SpektoWatch2Tests/AudioEngineTests" || true

echo ""
echo "5. ToneGenerator Tests (TEST-IE-052)"
run_tests "ToneGeneratorTests" "SpektoWatch2Tests/ToneGeneratorTests" || true

echo ""
echo "6. Integration Tests"
run_tests "IntegrationTests" "SpektoWatch2Tests/IntegrationTests" || true

# UI Tests
echo ""
echo "=========================================="
echo "UI TESTS"
echo "=========================================="

echo ""
echo "7. UI Tests (TEST-IE-001)"
run_tests "SpektoWatch2UITests" "SpektoWatch2UITests" || true

echo ""
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo ""
echo "Test results saved to: $PROJECT_DIR/TestResults/"
echo ""
echo "To view detailed results:"
echo "  open $PROJECT_DIR/TestResults/*.xcresult"
echo ""
echo "Done!"
