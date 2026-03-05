#!/bin/bash

# Whisper Free Deploy Script (Version 2.1)
cd "$(dirname "$0")"

APP_NAME="WhisperKiller"
BUNDLE_NAME="WhisperKiller.app"
INFO_PLIST="Sources/WhisperFree/Resources/Info.plist"
ICON_FILE="Sources/WhisperFree/Resources/AppIcon.icns"
BUILD_PATH=".build/apple/Products/Release/$APP_NAME"

# 1. Versioning
COMMIT_COUNT=$(git rev-list --count HEAD)
VERSION="2.0.$COMMIT_COUNT"
echo "🔢 Version: $VERSION (commits: $COMMIT_COUNT)"

# Update Info.plist before build
function update_plist() {
    local key=$1
    local value=$2
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$INFO_PLIST"
}

update_plist "CFBundleVersion" "$VERSION"
update_plist "CFBundleShortVersionString" "$VERSION"
update_plist "CFBundleExecutable" "$APP_NAME"

echo "🚀 Starting deployment v$VERSION..."

# 2. Kill existing process
echo "🔪 Cleaning up old instances..."
pkill -9 -x "WhisperKiller" || true
pkill -9 -x "WhisperFree" || true
rm -rf "WhisperFree.app"
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
    # Use -not -path to exclude dSYM files which often have the same name as the binary
    ACTUAL_BINARY=$(find .build -maxdepth 4 -name "$APP_NAME" -type f -not -path "*.dSYM*" | grep release | head -n 1)
    if [ -z "$ACTUAL_BINARY" ]; then
        echo "❌ Binary not found in .build directory."
        exit 1
    fi
    
    cp "$ACTUAL_BINARY" "$BUNDLE_NAME/Contents/MacOS/$APP_NAME"
    chmod +x "$BUNDLE_NAME/Contents/MacOS/$APP_NAME"
    cp "$INFO_PLIST" "$BUNDLE_NAME/Contents/Info.plist"
    if [ -f "$ICON_FILE" ]; then
        cp "$ICON_FILE" "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
    fi
    
    # Code sign with entitlements
    echo "🔑 Signing $BUNDLE_NAME with entitlements..."
    find "$BUNDLE_NAME" -type f -name "._*" -delete 2>/dev/null
    find "$BUNDLE_NAME" -type f -name ".DS_Store" -delete 2>/dev/null
    find "$BUNDLE_NAME" -exec xattr -c {} + 2>/dev/null
    
    ENTITLEMENTS="Sources/WhisperFree/Resources/WhisperKiller.entitlements"
    codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "Mikhail Drozdov" "$BUNDLE_NAME"
    
    # 5. Fix Permissions & Relocate
    echo "🏗️ Relocating to /Applications and fixing permissions..."
    ./scripts/fix_accessibility.sh
    
    echo "✨ $APP_NAME v$VERSION is now in /Applications and should be prompted for Accessibility."
    sleep 1
    osascript -e 'tell application "Terminal" to close (every window whose name contains "deploy.command")' &
    exit 0
else
    echo "❌ Build failed."
    exit 1
fi
