#!/bin/bash
# build_apk.sh - Run this script to build the release APK
# Requirements: Flutter SDK installed, Android SDK installed, JAVA_HOME set

set -e

echo "================================================"
echo "  Remotix - Release APK Build Script"
echo "================================================"

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "ERROR: Flutter not found in PATH"
    echo "Install from: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "[1/5] Flutter version:"
flutter --version

echo ""
echo "[2/5] Running flutter doctor..."
flutter doctor

echo ""
echo "[3/5] Running flutter clean..."
flutter clean

echo ""
echo "[4/5] Running flutter pub get..."
flutter pub get

echo ""
echo "[5/5] Building release APK..."
flutter build apk --release --target-platform android-arm,android-arm64,android-x64

echo ""
echo "================================================"
echo "  BUILD SUCCESS"
echo "================================================"
echo ""
echo "APK location:"
echo "  build/app/outputs/flutter-apk/app-release.apk"
echo ""
APK_SIZE=$(du -sh build/app/outputs/flutter-apk/app-release.apk 2>/dev/null | cut -f1 || echo "unknown")
echo "APK size: $APK_SIZE"
