import Quick
import Nimble
import Cocoa
@testable import Clipy

class HistoryFilterSpec: QuickSpec {
    override class func spec() {

        // Lightweight unmanaged CPYClip → ClipboardHistoryEntry helper
        // mirrors ClipboardHistoryEntrySpec — entries don't touch Realm at
        // read time, so plain instances are enough.
        func makeEntry(_ title: String, primaryKey: String = UUID().uuidString) -> ClipboardHistoryEntry {
            let clip = CPYClip()
            clip.title = title
            clip.dataHash = primaryKey
            clip.dataPath = "/tmp/\(primaryKey).data"
            clip.primaryType = NSPasteboard.PasteboardType.string.rawValue
            return ClipboardHistoryEntry(clip: clip)
        }

        describe("CPYClipboardHistoryWindowController.filter(entries:query:)") {

            it("returns the input unchanged when the query is empty") {
                let entries = [makeEntry("alpha"), makeEntry("beta"), makeEntry("gamma")]
                let result = CPYClipboardHistoryWindowController.filter(entries: entries, query: "")
                expect(result.count) == 3
                expect(result.map { $0.displayTitle }) == ["alpha", "beta", "gamma"]
            }

            it("treats whitespace-only queries as empty") {
                let entries = [makeEntry("alpha"), makeEntry("beta")]
                let result = CPYClipboardHistoryWindowController.filter(entries: entries, query: "   \n\t")
                expect(result.count) == 2
            }

            it("matches by case-insensitive substring") {
                let entries = [makeEntry("HelloWorld"), makeEntry("foobar"), makeEntry("HELLOmate")]
                let result = CPYClipboardHistoryWindowController.filter(entries: entries, query: "hello")
                expect(result.count) == 2
                expect(result.map { $0.displayTitle }).to(contain("HelloWorld"))
                expect(result.map { $0.displayTitle }).to(contain("HELLOmate"))
            }

            it("trims leading/trailing whitespace on the query before matching") {
                let entries = [makeEntry("hello"), makeEntry("world")]
                let result = CPYClipboardHistoryWindowController.filter(entries: entries, query: "   hello   ")
                expect(result.count) == 1
                expect(result.first?.displayTitle) == "hello"
            }

            it("returns an empty array when nothing matches") {
                let entries = [makeEntry("alpha"), makeEntry("beta")]
                let result = CPYClipboardHistoryWindowController.filter(entries: entries, query: "zzz")
                expect(result.isEmpty) == true
            }

            it("preserves the original ordering for matched entries") {
                let entries = [
                    makeEntry("AAA-1"),
                    makeEntry("BBB"),
                    makeEntry("aaa-2"),
                    makeEntry("AAA-3")
                ]
                let result = CPYClipboardHistoryWindowController.filter(entries: entries, query: "aaa")
                expect(result.map { $0.displayTitle }) == ["AAA-1", "aaa-2", "AAA-3"]
            }

            it("uses locale-aware matching for diacritics") {
                let entries = [makeEntry("café"), makeEntry("cafe")]
                // localizedCaseInsensitiveContains is locale-aware: depending on
                // locale, "cafe" may or may not match "café". Just verify that
                // the diacritic-bearing one always self-matches.
                let result = CPYClipboardHistoryWindowController.filter(entries: entries, query: "café")
                expect(result.map { $0.displayTitle }).to(contain("café"))
            }
        }
    }
}
