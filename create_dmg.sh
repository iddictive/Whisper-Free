#!/bin/bash
set -e

APP_NAME="WhisperFree"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
TEMP_DIR="dmg_temp"

echo "🔨 Building DMG for $APP_NAME..."

# 1. Build the app bundle using Makefile
make app

# 2. Setup temp directory
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cp -R "$APP_BUNDLE" "$TEMP_DIR/"

# 3. Create symlink to /Applications
ln -s /Applications "$TEMP_DIR/Applications"

# 4. Set Volume Icon (optional but professional)
# Note: This works best when creating the DMG from a folder
cp "Sources/WhisperFree/Resources/AppIcon.icns" "$TEMP_DIR/.VolumeIcon.icns"
# Set the custom icon bit on the folder before hdiutil
# (Requires SetFile from Xcode tools, which the user likely has)
command -v SetFile >/dev/null 2>&1 && SetFile -a C "$TEMP_DIR"

# 5. Create DMG
rm -f "$DMG_NAME"
hdiutil create -volname "$APP_NAME" -srcfolder "$TEMP_DIR" -ov -format UDZO "$DMG_NAME"

# 5. Cleanup
rm -rf "$TEMP_DIR"

echo "✅ DMG created: $DMG_NAME"
