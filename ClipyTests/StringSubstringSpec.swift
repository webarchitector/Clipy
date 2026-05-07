import Quick
import Nimble
import Foundation
@testable import Clipy

class StringSubstringSpec: QuickSpec {
    override class func spec() {
        describe("String[ClosedRange<Int>] subscript") {

            it("returns the requested slice for an in-range range") {
                expect("hello world"[0...4]) == "hello"
                expect("hello world"[6...10]) == "world"
            }

            it("clamps when upper bound exceeds string length (used by ClipService title cap)") {
                // ClipService.save calls data.preferredTitle[0...10000] without
                // checking length — the subscript must clamp instead of crashing.
                expect("short"[0...10000]) == "short"
            }

            it("returns empty when the range starts past the end") {
                expect("xyz"[100...200]) == ""
            }

            it("handles unicode scalars correctly (no UTF-16 confusion)") {
                // Emoji takes 1 Character but >1 UTF-16 code unit; the
                // subscript uses Character indices via index(_:offsetBy:).
                let s = "ab😀cd"
                expect(s[0...1]) == "ab"
                expect(s[2...2]) == "😀"
                expect(s[0...4]) == "ab😀cd"
            }

            it("works for empty strings") {
                expect(""[0...0]) == ""
                expect(""[0...100]) == ""
            }

            it("returns single character for zero-length range") {
                expect("hello"[2...2]) == "l"
            }
        }
    }
}
