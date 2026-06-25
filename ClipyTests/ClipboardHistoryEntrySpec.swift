// swiftlint:disable identifier_name

import Quick
import Nimble
import Cocoa
import RealmSwift
@testable import Clipy

class ClipboardHistoryEntrySpec: QuickSpec {
    override class func spec() {
        describe("ClipboardHistoryEntry.init(clip:)") {

            // The entry struct doesn't touch Realm beyond reading clip
            // properties, so unmanaged CPYClip instances are sufficient.
            func makeClip(title: String,
                          primaryType: NSPasteboard.PasteboardType = .string,
                          dataHash: String = "h",
                          dataPath: String = "/tmp/x.data",
                          thumbnailPath: String = "",
                          isColorCode: Bool = false) -> CPYClip {
                let clip = CPYClip()
                clip.title = title
                clip.dataHash = dataHash
                clip.dataPath = dataPath
                clip.primaryType = primaryType.rawValue
                clip.thumbnailPath = thumbnailPath
                clip.isColorCode = isColorCode
                return clip
            }

            describe("displayTitle") {
                it("trims surrounding whitespace") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "   hello   "))
                    expect(entry.displayTitle) == "hello"
                }

                it("keeps single-line input intact, collapsing internal whitespace") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "a   b\t c"))
                    expect(entry.displayTitle) == "a b c"
                }

                it("shows only the first line plus ellipsis for multi-line clips") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "a   b\n\n c\t\td"))
                    expect(entry.displayTitle) == "a b..."
                }

                it("collapses consecutive newlines into a single ellipsis") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "first\n\n\nsecond"))
                    expect(entry.displayTitle) == "first..."
                }

                it("treats trailing whitespace-only lines as single-line") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "only\n\n   \n"))
                    expect(entry.displayTitle) == "only"
                }

                it("caps at ~500 scalars to keep menu rendering cheap") {
                    let big = String(repeating: "x", count: 5_000)
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: big))
                    expect(entry.displayTitle.unicodeScalars.count) <= 500
                }
            }

            describe("fallback title") {
                it("falls back to (Image) for empty image clips") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "", primaryType: .png))
                    expect(entry.displayTitle) == "(Image)"
                }

                it("falls back to (PDF) for empty PDF clips") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "", primaryType: .pdf))
                    expect(entry.displayTitle) == "(PDF)"
                }

                it("falls back to (File) for empty file clips") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "", primaryType: .fileURL))
                    expect(entry.displayTitle) == "(File)"
                }

                it("falls back to (URL) for empty URL clips") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "", primaryType: .URL))
                    expect(entry.displayTitle) == "(URL)"
                }

                it("returns empty string for empty unknown-type clips") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "", primaryType: .string))
                    expect(entry.displayTitle) == ""
                }
            }

            describe("sanitized stored title") {
                it("treats `(Text)` as empty (legacy ClipService title placeholder)") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "(Text)", primaryType: .string))
                    expect(entry.displayTitle) == ""
                }

                it("treats `(Filenames)` as empty and falls back by primaryType") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "(Filenames)",
                                                                     primaryType: .fileURL))
                    expect(entry.displayTitle) == "(File)"
                }
            }

            describe("primary key + searchText + tooltip wiring") {
                it("uses dataHash as primaryKey") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "x", dataHash: "abc123"))
                    expect(entry.primaryKey) == "abc123"
                }

                it("searchText mirrors displayTitle for single-line clips") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "Hello   world"))
                    expect(entry.searchText) == entry.displayTitle
                }

                it("searchText keeps full flattened content for multi-line clips so cross-line queries match") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "foo\nbar"))
                    expect(entry.displayTitle) == "foo..."
                    expect(entry.searchText) == "foo bar"
                }

                it("toolTip mirrors flattened content, not the ellipsis-truncated display title") {
                    let entry = ClipboardHistoryEntry(clip: makeClip(title: "foo\nbar"))
                    expect(entry.toolTip) == "foo bar"
                }
            }

            describe("Equatable") {
                it("two entries from identical clips are equal") {
                    let a = ClipboardHistoryEntry(clip: makeClip(title: "x", dataHash: "h"))
                    let b = ClipboardHistoryEntry(clip: makeClip(title: "x", dataHash: "h"))
                    expect(a) == b
                }

                it("differs when primaryKey changes") {
                    let a = ClipboardHistoryEntry(clip: makeClip(title: "x", dataHash: "h1"))
                    let b = ClipboardHistoryEntry(clip: makeClip(title: "x", dataHash: "h2"))
                    expect(a) != b
                }
            }
        }
    }
}
