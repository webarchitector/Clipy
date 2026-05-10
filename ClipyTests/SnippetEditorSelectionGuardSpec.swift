import Quick
import Nimble
import Foundation
@testable import Clipy

class SnippetEditorSelectionGuardSpec: QuickSpec {
    override class func spec() {

        describe("SnippetEditorSelectionGuard.writeIsSafe") {

            it("rejects writes when nothing is displayed") {
                expect(SnippetEditorSelectionGuard.writeIsSafe(displayedID: nil, selectedID: nil)) == false
            }

            it("rejects writes when nothing is displayed but a snippet is selected") {
                expect(SnippetEditorSelectionGuard.writeIsSafe(displayedID: nil, selectedID: "snippet-A")) == false
            }

            it("rejects writes when the displayed snippet does not match the currently selected one") {
                expect(SnippetEditorSelectionGuard.writeIsSafe(displayedID: "snippet-A", selectedID: "snippet-B")) == false
            }

            it("allows writes when displayed and selected snippet identifiers match") {
                expect(SnippetEditorSelectionGuard.writeIsSafe(displayedID: "snippet-A", selectedID: "snippet-A")) == true
            }

            it("rejects writes when no snippet is currently selected even if something was displayed") {
                expect(SnippetEditorSelectionGuard.writeIsSafe(displayedID: "snippet-A", selectedID: nil)) == false
            }
        }
    }
}
