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

        // MenuManager isn't Sendable, KeyCombo's Sendable status varies by
        // Magnet version — under Swift 6 strict concurrency we instantiate
        // both per-test rather than capturing a shared `let` across @Sendable
        // `it` closures.

        describe("MenuManager.cgFlags(from:)") {

            it("translates a single Command flag") {
                let manager = MenuManager()
                expect(manager.cgFlags(from: [.command]) == .maskCommand) == true
            }

            it("translates a single Option flag") {
                let manager = MenuManager()
                expect(manager.cgFlags(from: [.option]) == .maskAlternate) == true
            }

            it("translates a single Control flag") {
                let manager = MenuManager()
                expect(manager.cgFlags(from: [.control]) == .maskControl) == true
            }

            it("translates a single Shift flag") {
                let manager = MenuManager()
                expect(manager.cgFlags(from: [.shift]) == .maskShift) == true
            }

            it("ORs combined modifiers") {
                let manager = MenuManager()
                let combined = manager.cgFlags(from: [.command, .shift])
                let expected: CGEventFlags = [.maskCommand, .maskShift]
                expect(combined == expected) == true
            }

            it("returns empty flags for no modifiers") {
                let manager = MenuManager()
                expect(manager.cgFlags(from: []) == []) == true
            }

            it("ignores caps-lock-style flags (numericPad, function, capsLock)") {
                let manager = MenuManager()
                let combined = manager.cgFlags(from: [.capsLock, .numericPad, .function, .command])
                expect(combined == .maskCommand) == true
            }
        }

        describe("MenuManager.matchesCGEvent(keyCode:flags:keyCombo:)") {

            it("matches when keyCode + modifiers exactly match") {
                let manager = MenuManager()
                let cmdShiftV = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey)!
                let flags: CGEventFlags = [.maskCommand, .maskShift]
                expect(manager.matchesCGEvent(keyCode: 9, flags: flags, keyCombo: cmdShiftV)) == true
            }

            it("rejects when keyCode differs") {
                let manager = MenuManager()
                let cmdShiftV = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey)!
                let flags: CGEventFlags = [.maskCommand, .maskShift]
                expect(manager.matchesCGEvent(keyCode: 11, flags: flags, keyCombo: cmdShiftV)) == false
            }

            it("rejects when modifiers differ") {
                let manager = MenuManager()
                let cmdShiftV = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey)!
                let flags: CGEventFlags = [.maskCommand]  // missing Shift
                expect(manager.matchesCGEvent(keyCode: 9, flags: flags, keyCombo: cmdShiftV)) == false
            }

            it("rejects when modifiers carry an extra flag") {
                let manager = MenuManager()
                let cmdShiftV = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey)!
                let flags: CGEventFlags = [.maskCommand, .maskShift, .maskControl]
                expect(manager.matchesCGEvent(keyCode: 9, flags: flags, keyCombo: cmdShiftV)) == false
            }

            it("returns false for a nil keyCombo (unconfigured hotkey)") {
                let manager = MenuManager()
                let flags: CGEventFlags = [.maskCommand, .maskShift]
                expect(manager.matchesCGEvent(keyCode: 9, flags: flags, keyCombo: nil)) == false
            }
        }
    }
}
