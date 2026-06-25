// swiftlint:disable identifier_name
import Quick
import Nimble
@testable import Clipy

class ScratchTitleSpec: QuickSpec {
    override class func spec() {
        describe("ScratchTitle.title(from:)") {
            it("returns empty for blank content") {
                expect(ScratchTitle.title(from: "")).to(equal(""))
                expect(ScratchTitle.title(from: "   \n\n  ")).to(equal(""))
            }
            it("returns the first non-empty trimmed line") {
                expect(ScratchTitle.title(from: "hello")).to(equal("hello"))
                expect(ScratchTitle.title(from: "\n\n  first \nsecond")).to(equal("first"))
                expect(ScratchTitle.title(from: "  spaced  ")).to(equal("spaced"))
            }
            it("truncates long lines with an ellipsis") {
                let long = String(repeating: "a", count: 100)
                let t = ScratchTitle.title(from: long, maxLength: 60)
                expect(t).to(equal(String(repeating: "a", count: 60) + "…"))
            }
        }
    }
}
