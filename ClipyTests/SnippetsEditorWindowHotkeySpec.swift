import Quick
import Nimble
import Cocoa
@testable import Clipy

class SnippetsEditorWindowHotkeySpec: QuickSpec {
    override class func spec() {
        describe("CPYSnippetsEditorWindow.shouldCloseForKeyEquivalent") {
            // Cmd+Q normally routes to NSApp.terminate(_:) and quits Clipy.
            // The editor overrides it to close just this window — users
            // dismissing the editor seldom want to quit the whole app.
            // Russian-PC layout: physical 'Q' produces Cyrillic 'й'.

            it("matches Cmd+Q with Latin 'q'") {
                expect(CPYSnippetsEditorWindow.shouldCloseForKeyEquivalent(chars: "q", mods: .command)) == true
            }

            it("matches Cmd+Q with Cyrillic 'й' (Russian-PC layout physical 'Q')") {
                expect(CPYSnippetsEditorWindow.shouldCloseForKeyEquivalent(chars: "й", mods: .command)) == true
            }

            it("matches uppercase 'Q' with Cmd (charactersIgnoringModifiers may be uppercase under Shift)") {
                expect(CPYSnippetsEditorWindow.shouldCloseForKeyEquivalent(chars: "Q", mods: .command)) == true
            }

            it("does NOT match plain 'q' without Cmd") {
                expect(CPYSnippetsEditorWindow.shouldCloseForKeyEquivalent(chars: "q", mods: [])) == false
            }

            it("does NOT match Cmd+Q combined with other modifiers (Cmd+Shift+Q would be a different binding)") {
                expect(CPYSnippetsEditorWindow.shouldCloseForKeyEquivalent(chars: "q", mods: [.command, .shift])) == false
            }

            it("does NOT match Cmd plus a different letter") {
                expect(CPYSnippetsEditorWindow.shouldCloseForKeyEquivalent(chars: "w", mods: .command)) == false
            }

            it("does NOT match nil chars") {
                expect(CPYSnippetsEditorWindow.shouldCloseForKeyEquivalent(chars: nil, mods: .command)) == false
            }
        }
    }
}
