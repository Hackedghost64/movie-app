#!/usr/bin/env bash
set -e

# MBX App - Production Release Build Script
# Includes:
# - R8 Full-Mode minification and dead-code stripping
# - Android resource shrinking
# - MaterialIcons font tree-shaking
# - Dart symbol obfuscation and split debug info
# - Per-ABI APK splitting (reduces download size to ~19.5MB for ARM64)

echo "=== Building MBX App (Production Release) ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$APP_DIR"

# Clean previous build symbols
mkdir -p build/app/outputs/symbols

# Run Flutter Release Build with ABI Split and Obfuscation
flutter build apk \
  --release \
  --split-per-abi \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols \
  --tree-shake-icons

echo ""
echo "=== Release Build Succeeded! ==="
echo "Artifacts generated in build/app/outputs/flutter-apk/:"
ls -lh build/app/outputs/flutter-apk/*.apk
echo ""
echo "Debug symbols archived in: build/app/outputs/symbols/"
