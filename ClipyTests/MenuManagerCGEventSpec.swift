import Quick
import Nimble
import Cocoa
import Carbon
import Magnet
@testable import Clipy

class MenuManagerCGEventSpec: QuickSpec {
    override class func spec() {
        // MenuManager owns the popup-switching event-tap glue. The two helpers
        // tested here are the only logic between a raw CGEvent / NSEvent and
        // "should this hotkey fire?", so a mismatch here lets the wrong
        // popup open or no popup at all.

        describe("MenuManager.cgFlags(from:)") {

            // Helper: instantiate without bind() side effects. MenuManager()
            // doesn't call setup() until something requests it.
            let manager = MenuManager()

            it("translates a single Command flag") {
                expect(manager.cgFlags(from: [.command]) == .maskCommand) == true
            }

            it("translates a single Option flag") {
                expect(manager.cgFlags(from: [.option]) == .maskAlternate) == true
            }

            it("translates a single Control flag") {
                expect(manager.cgFlags(from: [.control]) == .maskControl) == true
            }

            it("translates a single Shift flag") {
                expect(manager.cgFlags(from: [.shift]) == .maskShift) == true
            }

            it("ORs combined modifiers") {
                let combined = manager.cgFlags(from: [.command, .shift])
                let expected: CGEventFlags = [.maskCommand, .maskShift]
                expect(combined == expected) == true
            }

            it("returns empty flags for no modifiers") {
                expect(manager.cgFlags(from: []) == []) == true
            }

            it("ignores caps-lock-style flags (numericPad, function, capsLock)") {
                let combined = manager.cgFlags(from: [.capsLock, .numericPad, .function, .command])
                expect(combined == .maskCommand) == true
            }
        }

        describe("MenuManager.matchesCGEvent(keyCode:flags:keyCombo:)") {

            let manager = MenuManager()
            // ⌘⇧V — the default mainKeyCombo Clipy ships with.
            let cmdShiftV = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey)!

            it("matches when keyCode + modifiers exactly match") {
                let flags: CGEventFlags = [.maskCommand, .maskShift]
                expect(manager.matchesCGEvent(keyCode: 9, flags: flags, keyCombo: cmdShiftV)) == true
            }

            it("rejects when keyCode differs") {
                let flags: CGEventFlags = [.maskCommand, .maskShift]
                expect(manager.matchesCGEvent(keyCode: 11, flags: flags, keyCombo: cmdShiftV)) == false
            }

            it("rejects when modifiers differ") {
                let flags: CGEventFlags = [.maskCommand]  // missing Shift
                expect(manager.matchesCGEvent(keyCode: 9, flags: flags, keyCombo: cmdShiftV)) == false
            }

            it("rejects when modifiers carry an extra flag") {
                let flags: CGEventFlags = [.maskCommand, .maskShift, .maskControl]
                expect(manager.matchesCGEvent(keyCode: 9, flags: flags, keyCombo: cmdShiftV)) == false
            }

            it("returns false for a nil keyCombo (unconfigured hotkey)") {
                let flags: CGEventFlags = [.maskCommand, .maskShift]
                expect(manager.matchesCGEvent(keyCode: 9, flags: flags, keyCombo: nil)) == false
            }
        }
    }
}
