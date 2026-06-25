import Quick
import Nimble
@testable import Clipy

class LauncherScratchpadItemSpec: QuickSpec {
    override class func spec() {
        describe("LauncherItems.withScratchpad") {
            it("prepends a scratchpad item when the query is empty") {
                let out = LauncherItems.withScratchpad(prefixing: [.status("x")], query: "  ", noteCount: 3)
                guard case let .scratchpad(noteCount) = out.first else {
                    fail("expected .scratchpad first"); return
                }
                expect(noteCount) == 3
                expect(out.count) == 2
            }
            it("leaves results unchanged when the query is non-empty") {
                let out = LauncherItems.withScratchpad(prefixing: [.status("x")], query: "ab", noteCount: 3)
                expect(out.count) == 1
                if case .scratchpad = out.first { fail("did not expect scratchpad") }
            }
        }
    }
}
