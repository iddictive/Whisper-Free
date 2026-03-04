#!/bin/bash

# Whisper Free Deploy Script (Version 2.0)
# This script builds, packages the .app bundle, launches it, and closes the terminal.
cd "$(dirname "$0")"
APP_NAME="WhisperFree"
BUNDLE_NAME="WhisperFree.app"
# 2. Versioning (Spoof Style)
COMMIT_COUNT=$(git rev-list --count HEAD)
VERSION="2.0.$COMMIT_COUNT"

# Update Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"

echo "🚀 Starting deployment v$VERSION..."

# 1. Kill existing process aggressively
echo "🔪 Cleaning up old $APP_NAME instances..."
pkill -9 -x "$APP_NAME" || true
# Wait a moment for the OS to release resources
sleep 1

# 2. Build release
echo "📦 Building release version $VERSION..."
swift build -c release

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # 3. Packaging into .app bundle in the project folder
    echo "🏗️ Packaging into $BUNDLE_NAME..."
    mkdir -p "$BUNDLE_NAME/Contents/MacOS"
    mkdir -p "$BUNDLE_NAME/Contents/Resources"
    
    # Copy new binary
    cp "$BUILD_PATH" "$BUNDLE_NAME/Contents/MacOS/$APP_NAME"
    # Copy Info.plist
    cp "$INFO_PLIST" "$BUNDLE_NAME/Contents/Info.plist"
    # Copy Icon if exists
    if [ -f "$ICON_FILE" ]; then
        cp "$ICON_FILE" "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
    fi
    
    # 4. Running from the bundle
    echo "🏃 Launching $BUNDLE_NAME..."
    open "$BUNDLE_NAME"
    
    echo "✨ $APP_NAME v$VERSION is now running from the bundle in this folder."
    echo "This window will close automatically in 2 seconds..."
sleep 2
osascript -e 'tell application "Terminal" to close (every window whose name contains "deploy.command")' &
    exit 0
else
    echo "❌ Build failed. Please check the logs above."
    read -p "Press enter to exit..."
    exit 1
fi
