import Quick
import Nimble
import Foundation
@testable import Clipy

class ClipServicePasswordHeuristicSpec: QuickSpec {
    override class func spec() {
        describe("ClipService.looksLikePassword") {

            describe("rejects (returns false) for") {

                it("empty strings") {
                    expect(ClipService.looksLikePassword("")) == false
                }

                it("plain English text with spaces") {
                    expect(ClipService.looksLikePassword("hello world")) == false
                }

                it("strings with whitespace anywhere — passwords don't have spaces") {
                    expect(ClipService.looksLikePassword("Abcd1!ef gh")) == false
                }

                it("strings missing a digit") {
                    expect(ClipService.looksLikePassword("Abcdef!")) == false
                }

                it("strings missing a special character") {
                    expect(ClipService.looksLikePassword("Abcdef12")) == false
                }

                it("strings missing uppercase") {
                    expect(ClipService.looksLikePassword("abcdef1!")) == false
                }

                it("strings missing lowercase") {
                    expect(ClipService.looksLikePassword("ABCDEF1!")) == false
                }

                it("strings longer than 128 scalars (presumed prose, not a password)") {
                    let long = String(repeating: "Aa1!", count: 33) // 132 scalars
                    expect(ClipService.looksLikePassword(long)) == false
                }
            }

            describe("flags (returns true) for") {

                it("typical strong passwords (mixed case + digit + special)") {
                    expect(ClipService.looksLikePassword("Tr0ub4dor&3")) == true
                    expect(ClipService.looksLikePassword("Abc12345!")) == true
                    expect(ClipService.looksLikePassword("P@ssw0rd")) == true
                }

                it("the boundary length 128 still triggers when content matches") {
                    // 32 reps of "Aa1!" = 128 scalars
                    let boundary = String(repeating: "Aa1!", count: 32)
                    expect(ClipService.looksLikePassword(boundary)) == true
                }
            }
        }
    }
}
