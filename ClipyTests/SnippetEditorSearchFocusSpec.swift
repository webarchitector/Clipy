// swiftlint:disable identifier_name

import Quick
import Nimble
import Cocoa
@testable import Clipy

// Regression: the snippets editor controller is the delegate of BOTH the outline
// view (inline rename) and the search field. The shared
// NSControlTextEditingDelegate method `control(_:textShouldEndEditing:)` must
// only veto editing for the outline view. Returning false for the search field
// refuses to end editing, which traps first responder on the search field — so
// outline clicks and drag-and-drop stop working (the dragged row will not lift)
// and the search field can no longer be unfocused.
class SnippetEditorSearchFocusSpec: QuickSpec {
    override class func spec() {
        describe("control(_:textShouldEndEditing:)") {
            it("lets the search field end editing so focus is not trapped") {
                let controller = CPYSnippetsEditorWindowController(windowNibName: "CPYSnippetsEditorWindowController")
                let searchField = NSSearchField()
                let editor = NSText()

                // Empty query — the exact case that fired on the first click.
                editor.string = ""
                expect(controller.control(searchField, textShouldEndEditing: editor)).to(beTrue())

                // Non-empty query.
                editor.string = "foo"
                expect(controller.control(searchField, textShouldEndEditing: editor)).to(beTrue())
            }

            // Same class of bug: `control(_:textView:doCommandBy:)` fires for the
            // outline view too (inline rename). Escape during a rename must fall
            // through to the default abort, not the search field's Escape handler.
            it("ignores doCommandBy from controls other than the search field") {
                let controller = CPYSnippetsEditorWindowController(windowNibName: "CPYSnippetsEditorWindowController")
                let outlineView = NSOutlineView()
                let editor = NSTextView()
                let handled = controller.control(outlineView,
                                                 textView: editor,
                                                 doCommandBy: #selector(NSResponder.cancelOperation(_:)))
                expect(handled).to(beFalse())
            }
        }
    }
}
