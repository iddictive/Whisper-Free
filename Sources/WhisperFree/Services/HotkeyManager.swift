import Cocoa
import Carbon

final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var isKeyDown = false

    /// Current hotkey config — can be updated at runtime
    var config = HotkeyConfig()
    
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Explicitly check trust including prompt if needed
    func checkTrust(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }


    deinit {
        stop()
    }

    func start(promptUser: Bool = false, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): promptUser] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            if promptUser {
                print("⚠️ Accessibility permission required for global hotkeys")
            }
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | 
                                    (1 << CGEventType.keyUp.rawValue) | 
                                    (1 << CGEventType.flagsChanged.rawValue)

        // Try to intercept Dictation key (F5-like system keys)
        NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            // Subtype 20 is often associated with the Dictation key trigger
            if event.subtype.rawValue == 20 {
                self?.onKeyDown?()
                // Note: Global monitors don't allow blocking the event, 
                // but a tap might if we knew the exact CGEvent details for the Dictation key.
            }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap. Check accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isKeyDown = false // Reset state on stop
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // DEBUG: Print all keycodes to find Dictation key
        // print("DEBUG: KeyCode: \(keyCode), Flags: \(flags.rawValue)")

        // Check against configured hotkey
        let matchesKey = Int(keyCode) == config.keyCode
        let matchesMods = checkModifiers(flags)

        if matchesKey && matchesMods {
            if type == .keyDown {
                // Prevent duplicate key-down events from key repeat triggering onKeyDown multiple times
                if !isKeyDown {
                    isKeyDown = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onKeyDown?()
                    }
                }
                // SWALLOW the event so the OS (or frontmost app) doesn't receive the keystroke
                return nil
            } else if type == .keyUp {
                if isKeyDown {
                    isKeyDown = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onKeyUp?()
                    }
                }
                // SWALLOW the key release too
                return nil
            }
        }

        // Handle modifier key release while key was held.
        // Only react when the hotkey's OWN required modifiers are released,
        // NOT when unrelated modifiers change (e.g. Cmd during Cmd-Tab).
        if type == .flagsChanged && isKeyDown && !hotkeyModifiersStillHeld(flags) {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func checkModifiers(_ flags: CGEventFlags) -> Bool {
        let needOption  = config.useOption
        let needCommand = config.useCommand
        let needControl = config.useControl
        let needShift   = config.useShift

        let hasOption  = flags.contains(.maskAlternate)
        let hasCommand = flags.contains(.maskCommand)
        let hasControl = flags.contains(.maskControl)
        let hasShift   = flags.contains(.maskShift)

        return (needOption == hasOption) &&
               (needCommand == hasCommand) &&
               (needControl == hasControl) &&
               (needShift == hasShift)
    }

    /// Checks ONLY the modifiers that the hotkey requires are still held.
    /// Unlike `checkModifiers` which requires an exact match, this ignores
    /// extra modifiers (e.g. Cmd pressed during Cmd-Tab won't cause a false release).
    private func hotkeyModifiersStillHeld(_ flags: CGEventFlags) -> Bool {
        if config.useOption  && !flags.contains(.maskAlternate) { return false }
        if config.useCommand && !flags.contains(.maskCommand)   { return false }
        if config.useControl && !flags.contains(.maskControl)   { return false }
        if config.useShift   && !flags.contains(.maskShift)     { return false }
        return true
    }
}
