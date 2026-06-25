import Quick
import Nimble
@testable import Clipy

class ScratchTitleSpec: QuickSpec {
    override class func spec() {
        describe("ScratchTitle.title(from:)") {
            it("returns empty for blank content") {
                expect(ScratchTitle.title(from: "")) == ""
                expect(ScratchTitle.title(from: "   \n\n  ")) == ""
            }
            it("returns the first non-empty trimmed line") {
                expect(ScratchTitle.title(from: "hello")) == "hello"
                expect(ScratchTitle.title(from: "\n\n  first \nsecond")) == "first"
                expect(ScratchTitle.title(from: "  spaced  ")) == "spaced"
            }
            it("truncates long lines with an ellipsis") {
                let long = String(repeating: "a", count: 100)
                expect(ScratchTitle.title(from: long, maxLength: 60)) == String(repeating: "a", count: 60) + "…"
            }
        }
    }
}
