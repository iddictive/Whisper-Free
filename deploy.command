#!/bin/bash

# Whisper Free Deploy Script (Version 2.1)
cd "$(dirname "$0")"

APP_NAME="WhisperFree"
BUNDLE_NAME="WhisperFree.app"
INFO_PLIST="Sources/WhisperFree/Resources/Info.plist"
ICON_FILE="Sources/WhisperFree/Resources/AppIcon.icns"
BUILD_PATH=".build/apple/Products/Release/$APP_NAME"

# 1. Versioning
COMMIT_COUNT=$(git rev-list --count HEAD)
VERSION="2.0.$COMMIT_COUNT"
echo "🔢 Version: $VERSION (commits: $COMMIT_COUNT)"

# Update Info.plist before build
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$INFO_PLIST"

echo "🚀 Starting deployment v$VERSION..."

# 2. Kill existing process
echo "🔪 Cleaning up old $APP_NAME instances..."
pkill -9 -x "$APP_NAME" || true
sleep 1

# 3. Build release
echo "📦 Building release version $VERSION..."
swift build -c release --arch arm64

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # 4. Packaging
    echo "🏗️ Packaging into $BUNDLE_NAME..."
    rm -rf "$BUNDLE_NAME"
    mkdir -p "$BUNDLE_NAME/Contents/MacOS"
    mkdir -p "$BUNDLE_NAME/Contents/Resources"
    
    # Copy binary - find it if path is different
    ACTUAL_BINARY=$(find .build -name "$APP_NAME" -type f | grep release | head -n 1)
    if [ -z "$ACTUAL_BINARY" ]; then
        echo "❌ Binary not found in .build directory."
        exit 1
    fi
    
    cp "$ACTUAL_BINARY" "$BUNDLE_NAME/Contents/MacOS/$APP_NAME"
    cp "$INFO_PLIST" "$BUNDLE_NAME/Contents/Info.plist"
    if [ -f "$ICON_FILE" ]; then
        cp "$ICON_FILE" "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
    fi
    
    # 5. Launch
    echo "🏃 Launching $BUNDLE_NAME..."
    open "$BUNDLE_NAME"
    
    echo "✨ $APP_NAME v$VERSION is running."
    sleep 1
    osascript -e 'tell application "Terminal" to close (every window whose name contains "deploy.command")' &
    exit 0
else
    echo "❌ Build failed."
    exit 1
fi
