.PHONY: install build run clean app

# One-click install (build + launch)
install:
	@bash deploy.command

# Build release
build:
	swift build -c release

# Build debug + run
run:
	swift run WhisperKiller

# Create .app bundle from release build
app: build
	@mkdir -p WhisperKiller.app/Contents/MacOS
	@mkdir -p WhisperKiller.app/Contents/Resources
	@cp .build/release/WhisperKiller WhisperKiller.app/Contents/MacOS/
	@cp Sources/WhisperFree/Resources/Info.plist WhisperKiller.app/Contents/
	@cp Sources/WhisperFree/Resources/AppIcon.icns WhisperKiller.app/Contents/Resources/
	@echo "✅ WhisperKiller.app created"
	@echo "   Run: open WhisperKiller.app"

# Clean build artifacts
clean:
	swift package clean
	rm -rf WhisperKiller.app

# Open in Xcode
xcode:
	open Package.swift
