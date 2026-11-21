#!/bin/bash
# Builds a signed release APK: export/westbridge-<version>.apk (Android, arm64).
# Requirements:
#   - Godot 4.7.1 with the Android export templates installed (~/.local/share/godot/export_templates/4.7.1.stable/)
#   - Editor Settings: export/android/android_sdk_path -> an Android SDK with platform-tools and build-tools (apksigner),
#     export/android/debug_keystore -> a debug keystore
#   - a release keystore, passed through the environment (never commit it):
#       KEYSTORE=/path/release.keystore KEY_ALIAS=westbridge KEY_PASS=... ./tools/build_apk.sh
cd "$(dirname "$0")/.." || exit 1
source tools/env.sh
: "${KEYSTORE:?set KEYSTORE}" "${KEY_ALIAS:?set KEY_ALIAS}" "${KEY_PASS:?set KEY_PASS}"
version=$(grep -m1 '^version/name=' export_presets.cfg | cut -d'"' -f2)
mkdir -p export
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE" GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KEY_ALIAS" \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KEY_PASS" \
	$GODOT --headless --path . --export-release "Android" "export/westbridge-$version.apk"
