import Quick
import Nimble
import Cocoa
@testable import Clipy

class HistoryControllerHelpersSpec: QuickSpec {
    override class func spec() {

        // Lightweight unmanaged CPYClip wrapper — entries don't hit Realm
        // at read time so plain instances work.
        func makeEntry(title: String = "x", primaryKey: String) -> ClipboardHistoryEntry {
            let clip = CPYClip()
            clip.title = title
            clip.dataHash = primaryKey
            clip.dataPath = "/tmp/\(primaryKey).data"
            clip.primaryType = NSPasteboard.PasteboardType.string.rawValue
            return ClipboardHistoryEntry(clip: clip)
        }

        describe("CPYClipboardHistoryWindowController.restoreIndex(in:primaryKey:)") {

            it("returns nil for an empty list (caller must clear selection)") {
                let result = CPYClipboardHistoryWindowController
                    .restoreIndex(in: [], primaryKey: "anything")
                expect(result).to(beNil())
            }

            it("returns the row of the previously-selected primary key when present") {
                let entries = [makeEntry(primaryKey: "a"),
                               makeEntry(primaryKey: "b"),
                               makeEntry(primaryKey: "c")]
                expect(CPYClipboardHistoryWindowController.restoreIndex(in: entries, primaryKey: "b")) == 1
                expect(CPYClipboardHistoryWindowController.restoreIndex(in: entries, primaryKey: "c")) == 2
            }

            it("falls back to row 0 when the prior key is no longer in the list") {
                let entries = [makeEntry(primaryKey: "x"), makeEntry(primaryKey: "y")]
                expect(CPYClipboardHistoryWindowController.restoreIndex(in: entries, primaryKey: "gone")) == 0
            }

            it("falls back to row 0 when no prior key was set") {
                let entries = [makeEntry(primaryKey: "x"), makeEntry(primaryKey: "y")]
                expect(CPYClipboardHistoryWindowController.restoreIndex(in: entries, primaryKey: nil)) == 0
            }
        }

        describe("CPYClipboardHistoryWindowController.quickPasteIndex(forDigit:)") {

            it("maps Cmd+1…9 to row 0…8") {
                for digit in 1...9 {
                    expect(CPYClipboardHistoryWindowController.quickPasteIndex(forDigit: digit)) == digit - 1
                }
            }

            it("maps Cmd+0 to row 9 (the tenth visible clip)") {
                expect(CPYClipboardHistoryWindowController.quickPasteIndex(forDigit: 0)) == 9
            }

            it("returns nil for digits outside 0…9") {
                expect(CPYClipboardHistoryWindowController.quickPasteIndex(forDigit: -1)).to(beNil())
                expect(CPYClipboardHistoryWindowController.quickPasteIndex(forDigit: 10)).to(beNil())
                expect(CPYClipboardHistoryWindowController.quickPasteIndex(forDigit: 99)).to(beNil())
            }
        }

        describe("CPYClipboardHistoryWindowController.primaryKeysToDelete(at:in:)") {

            it("collects keys for every selected row, in selection order") {
                let entries = [makeEntry(primaryKey: "a"),
                               makeEntry(primaryKey: "b"),
                               makeEntry(primaryKey: "c"),
                               makeEntry(primaryKey: "d")]
                let result = CPYClipboardHistoryWindowController
                    .primaryKeysToDelete(at: IndexSet([1, 3]), in: entries)
                expect(result) == ["b", "d"]
            }

            it("returns an empty array for an empty selection") {
                let entries = [makeEntry(primaryKey: "a")]
                let result = CPYClipboardHistoryWindowController
                    .primaryKeysToDelete(at: IndexSet(), in: entries)
                expect(result.isEmpty) == true
            }

            it("silently drops out-of-range indexes (defensive against stale selection)") {
                let entries = [makeEntry(primaryKey: "a"), makeEntry(primaryKey: "b")]
                // 99 is out of range — must not crash, must not appear in output.
                let result = CPYClipboardHistoryWindowController
                    .primaryKeysToDelete(at: IndexSet([0, 99]), in: entries)
                expect(result) == ["a"]
            }

            it("handles a fully out-of-range selection without crashing") {
                let entries = [makeEntry(primaryKey: "a")]
                let result = CPYClipboardHistoryWindowController
                    .primaryKeysToDelete(at: IndexSet([5, 6, 7]), in: entries)
                expect(result.isEmpty) == true
            }
        }
    }
}
