//
//  HIDHotKeyTap.swift
//
//  Higher-priority hotkey delivery via CGEventTap at HID level.
//
//  Why this exists:
//  Magnet/Carbon `RegisterEventHotKey` is normally sufficient for global
//  hotkeys, but it loses to apps that install their own CGEventTap and
//  consume keyboard events when they are foreground (Zoom is the canonical
//  offender — its push-to-talk / annotation tap eats Cmd+Space and our
//  per-input-source layout shortcuts before WindowServer routes them to
//  the Carbon hotkey dispatcher).
//
//  This tap is installed at .cghidEventTap with .headInsertEventTap so it
//  sees keyDown events earlier than session-level taps. On match against a
//  HotKey already registered with Magnet's HotKeyCenter, we invoke the
//  hotkey's action and consume the event so neither Carbon nor the focused
//  app see it. On miss, we pass the event through unchanged.
//
//  Permission: requires Input Monitoring (System Settings → Privacy &
//  Security → Input Monitoring). Without it `CGEvent.tapCreate` returns nil
//  and we fall back silently to plain Magnet (still works in non-Zoom
//  contexts).
//

import Cocoa
import Carbon
import IOKit.hid
import Magnet

// install() and tap state are touched only on the main thread. The
// CGEventTap callback runs on a kernel-side thread but reaches the
// instance via Unmanaged.fromOpaque, never via Swift-managed isolation.
// @unchecked Sendable keeps this dual-life pattern intact under Swift 6.
final class HIDHotKeyTap: @unchecked Sendable {

    static let shared = HIDHotKeyTap()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var didPromptForPermission = false

    private init() {}

    func install() {
        guard eventTap == nil else { return }

        // Synchronously prompts the user the first time; subsequent calls
        // return the cached decision. If denied, tapCreate below returns nil
        // and we leave Magnet alone.
        if !didPromptForPermission {
            didPromptForPermission = true
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<HIDHotKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: refcon) else {
            NSLog("HIDHotKeyTap: tapCreate failed — Input Monitoring permission likely missing. Magnet hotkeys will still fire when no other app intercepts the event.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable the tap if the system disabled it (long callbacks, sleep, etc.).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let carbonModifiers = HIDHotKeyTap.carbonModifiers(from: event.flags)

        // Match against the keyCode Carbon was actually registered with,
        // not `keyCombo.currentKeyCode` — the latter goes through Sauce
        // which recomputes per call against the currently active layout
        // and can drift after the user switches between layouts (e.g. EN
        // → RU). When drift hits, the match misses, the tap passes the
        // event through, and the focused app silently eats it, which
        // surfaces as "the layout-switch hotkey works every other press".
        let match = HotKeyCenter.shared.registeredHotKeys.first { hotKey in
            !hotKey.keyCombo.doubledModifiers &&
                hotKey.registeredKeyCode == keyCode &&
                hotKey.keyCombo.modifiers == carbonModifiers
        }

        guard let hotKey = match else {
            return Unmanaged.passUnretained(event)
        }

        // HotKey.invoke() already dispatches to the configured ActionQueue
        // (typically main-async), so we return immediately and consume the
        // event so the focused app's tap (e.g. Zoom) never sees it.
        hotKey.invoke()
        return nil
    }

    // Visible to tests via `@testable import Clipy`.
    static func carbonModifiers(from flags: CGEventFlags) -> Int {
        var result = 0
        if flags.contains(.maskCommand) { result |= cmdKey }
        if flags.contains(.maskAlternate) { result |= optionKey }
        if flags.contains(.maskControl) { result |= controlKey }
        if flags.contains(.maskShift) { result |= shiftKey }
        return result
    }
}
