import Quick
import Nimble
import Cocoa
@testable import Clipy

class ClipboardHistoryPanelHotkeySpec: QuickSpec {
    override class func spec() {
        describe("ClipboardHistoryPanel.performKeyEquivalent — Cmd+O alias") {
            // Russian-PC-layout maps physical 'O' to Cyrillic 'щ' and physical
            // 'J' to Cyrillic 'о'. The alias for "open in default app" must
            // therefore match 'o' || 'щ' — never 'о', which would also fire
            // on Cmd+J on Russian and miss Cmd+O. Regression seed: pre-fix
            // the alias was 'o' || 'о' and behaved exactly the wrong way.
            func makeEvent(chars: String, mods: NSEvent.ModifierFlags) -> NSEvent {
                return NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: mods,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: chars,
                    charactersIgnoringModifiers: chars,
                    isARepeat: false,
                    keyCode: 0
                )!
            }

            it("fires for Latin 'o' with Command") {
                let panel = ClipboardHistoryPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                    styleMask: [.borderless], backing: .buffered, defer: true
                )
                var fired = false
                panel.openInDefaultAppHandler = { fired = true }
                let event = makeEvent(chars: "o", mods: .command)
                _ = panel.performKeyEquivalent(with: event)
                expect(fired) == true
            }

            it("fires for Cyrillic 'щ' (Russian-layout physical 'O')") {
                let panel = ClipboardHistoryPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                    styleMask: [.borderless], backing: .buffered, defer: true
                )
                var fired = false
                panel.openInDefaultAppHandler = { fired = true }
                let event = makeEvent(chars: "щ", mods: .command)
                _ = panel.performKeyEquivalent(with: event)
                expect(fired) == true
            }

            it("does NOT fire for Cyrillic 'о' (which is on physical 'J')") {
                let panel = ClipboardHistoryPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                    styleMask: [.borderless], backing: .buffered, defer: true
                )
                var fired = false
                panel.openInDefaultAppHandler = { fired = true }
                let event = makeEvent(chars: "о", mods: .command)
                _ = panel.performKeyEquivalent(with: event)
                expect(fired) == false
            }

            it("does NOT fire without Command") {
                let panel = ClipboardHistoryPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                    styleMask: [.borderless], backing: .buffered, defer: true
                )
                var fired = false
                panel.openInDefaultAppHandler = { fired = true }
                _ = panel.performKeyEquivalent(with: makeEvent(chars: "o", mods: []))
                _ = panel.performKeyEquivalent(with: makeEvent(chars: "щ", mods: []))
                expect(fired) == false
            }
        }
    }
}
