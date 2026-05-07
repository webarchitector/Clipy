// swiftlint:disable identifier_name

import Quick
import Nimble
import Foundation
@testable import Clipy

class StringSubstringSpec: QuickSpec {
    override class func spec() {
        describe("String[ClosedRange<Int>] subscript") {

            // Important quirk: despite using ClosedRange, the implementation
            // computes `self[start..<end]` (half-open). So `[0...N]` yields
            // the *first N characters*, not N+1. The only production caller
            // is `data.preferredTitle[0...10000]` (a length cap), where
            // half-open semantics are exactly what we want.

            it("returns the first upperBound characters for an in-range range") {
                expect("hello world"[0...4]) == "hell"
                expect("hello world"[6...10]) == "worl"
            }

            it("clamps when upper bound exceeds string length (used by ClipService title cap)") {
                // ClipService.save calls data.preferredTitle[0...10000] without
                // checking length — the subscript must clamp instead of crashing.
                expect("short"[0...10000]) == "short"
            }

            it("returns the full string when both bounds clamp past endIndex") {
                // Both ?? fallbacks fire (lower → startIndex, upper → endIndex),
                // producing a full-string slice. Quirky but stable.
                expect("xyz"[100...200]) == "xyz"
            }

            it("counts by Character (so emoji are one slot, not multiple UTF-16 units)") {
                let s = "ab😀cd"
                expect(s[0...1]) == "a"
                expect(s[0...3]) == "ab😀"
                expect(s[0...5]) == "ab😀cd"
            }

            it("works for empty strings") {
                expect(""[0...0]) == ""
                expect(""[0...100]) == ""
            }

            it("returns empty string for a zero-width range (lower == upper)") {
                expect("hello"[2...2]) == ""
            }
        }
    }
}
