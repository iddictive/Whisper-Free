.PHONY: all help install verify run app clean purge

# Default target: build and verify
all: verify

help:
	@echo "WhisperKiller Build System"
	@echo "  make install - Build, verify, sign, move to /Applications, and launch"
	@echo "  make verify  - Full compile check (debug & release)"
	@echo "  make run     - Build debug and run immediately"
	@echo "  make app     - Create a local .app bundle"
	@echo "  make clean   - Remove build artifacts and local .app bundles"
	@echo "  make purge   - Remove all temporary logs and trash files"

# One-click install (verify + build + sign + move to /Applications + launch)
install: verify
	@bash scripts/deploy.sh

# Verify the whole project compiles without errors
verify:
	@echo "🔍 Verifying project integrity..."
	@swift build
	@swift build -c release
	@echo "✅ All files compiled successfully"

# Build debug + run
run:
	swift run WhisperKiller

# Build release bundle locally
app: verify
	@mkdir -p WhisperKiller.app/Contents/MacOS
	@mkdir -p WhisperKiller.app/Contents/Resources
	@cp .build/release/WhisperKiller WhisperKiller.app/Contents/MacOS/
	@cp Sources/WhisperFree/Resources/Info.plist WhisperKiller.app/Contents/
	@cp Sources/WhisperFree/Resources/AppIcon.icns WhisperKiller.app/Contents/Resources/
	@echo "✅ WhisperKiller.app created locally"

# Clean build artifacts
clean:
	@swift package clean
	@rm -rf WhisperKiller.app
	@rm -rf WhisperFlow.app
	@echo "🧹 Build artifacts cleaned"

# Deep clean of all trash files and logs
purge: clean
	@rm -f deploy_log*.txt
	@rm -f crash_logs.txt
	@rm -f debug_paths.swift
	@rm -rf "WhisperFree Exports"
	@echo "🗑️  All temporary logs and trash files removed"

# Open in Xcode
xcode:
	open Package.swift
