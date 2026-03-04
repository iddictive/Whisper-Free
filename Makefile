.PHONY: install build run clean app

# One-click install (dependencies + build + app bundle)
install:
	@./install.sh

# Build release
build:
	swift build -c release

# Build debug + run
run:
	swift run WhisperFree

# Create .app bundle from release build
app: build
	@mkdir -p WhisperFree.app/Contents/MacOS
	@mkdir -p WhisperFree.app/Contents/Resources
	@mkdir -p WhisperFree.app/Contents/Frameworks
	@cp .build/release/WhisperFree WhisperFree.app/Contents/MacOS/
	@cp Sources/WhisperFree/Resources/Info.plist WhisperFree.app/Contents/
	@cp Sources/WhisperFree/Resources/AppIcon.icns WhisperFree.app/Contents/Resources/
	@cp -R .build/arm64-apple-macosx/release/Sparkle.framework WhisperFree.app/Contents/Frameworks/
	@install_name_tool -add_rpath "@executable_path/../Frameworks" WhisperFree.app/Contents/MacOS/WhisperFree
	@echo "✅ WhisperFree.app created with Sparkle"
	@echo "   Run: open WhisperFree.app"

# Clean build artifacts
clean:
	swift package clean
	rm -rf WhisperFree.app

# Open in Xcode
xcode:
	open Package.swift
