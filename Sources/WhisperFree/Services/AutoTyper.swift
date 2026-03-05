import Cocoa

final class AutoTyper {

    /// Inserts text into the active application using the selected method
    static func insert(text: String, method: InsertionMethod) {
        switch method {
        case .paste:
            simulatePaste()
        case .type:
            typeDirectly(text)
        }
    }

    /// Simulates Cmd+V to paste the current contents of the general pasteboard
    static func simulatePaste() {
        // Small delay to ensure the active application is ready after our overlay closes
        usleep(50_000) // 50ms

        // Simulate ⌘+V using CGEvent
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'v' key
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Directly "types" text into the focused application without using the clipboard
    static func typeDirectly(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Small delay to ensure the active application is ready
        usleep(50_000) // 50ms

        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Replace newlines with carriage returns. 
        // Many macOS apps treat \r as "newline without submitting" in text fields.
        let correctedText = text.replacingOccurrences(of: "\n", with: "\r")
        
        // For better stability with virtual events, we post characters one by one or in small chunks.
        // Also ensure no modifiers are accidentally active from previous events.
        for char in correctedText.utf16 {
            let utf16Chars = [char]
            
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            
            keyDown?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            
            // Post with a tiny delay if needed, but usually back-to-back is fine for unicode
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Emergency release of all major modifier keys
    static func releaseModifiers() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keys: [Int] = [
            0x38, // Shift
            0x3B, // Control
            0x3A, // Option
            0x37  // Command
        ]
        
        for key in keys {
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Simulates pressing the Return (Enter) key
    static func simulateReturn() {
        // Small delay to ensure the previous text insertion is processed
        usleep(50_000) // 50ms

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 36 // Return key

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

