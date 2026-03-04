.PHONY: install build run clean app

# One-click install (build + launch)
install:
	@bash deploy.command

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
	@cp .build/release/WhisperFree WhisperFree.app/Contents/MacOS/
	@cp Sources/WhisperFree/Resources/Info.plist WhisperFree.app/Contents/
	@cp Sources/WhisperFree/Resources/AppIcon.icns WhisperFree.app/Contents/Resources/
	@echo "✅ WhisperFree.app created"
	@echo "   Run: open WhisperFree.app"

# Clean build artifacts
clean:
	swift package clean
	rm -rf WhisperFree.app

# Open in Xcode
xcode:
	open Package.swift
