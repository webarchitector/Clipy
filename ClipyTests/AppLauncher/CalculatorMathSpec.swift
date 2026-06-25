import Quick
import Nimble
import Foundation
@testable import Clipy

class CalculatorMathSpec: QuickSpec {
    override class func spec() {
        describe("Calculator.evaluateMath") {

            it("evaluates basic arithmetic") {
                expect(Calculator.evaluateMath("1+2")) == "3"
                expect(Calculator.evaluateMath("(1+2)*3")) == "9"
                expect(Calculator.evaluateMath("10/4")) == "2.5"
            }

            it("supports the ^ alias for exponentiation") {
                expect(Calculator.evaluateMath("2^10")) == "1024"
            }

            it("handles sqrt() via a regex pre-pass") {
                expect(Calculator.evaluateMath("sqrt(4)")) == "2"
                expect(Calculator.evaluateMath("sqrt(2)")) == "1.41421"
            }

            it("returns nil for divide-by-zero") {
                expect(Calculator.evaluateMath("1/0")) == nil
            }

            it("formats integral results without a decimal when the input is integral") {
                expect(Calculator.evaluateMath("3")) == "3"
                expect(Calculator.evaluateMath("1+2")) == "3"
                expect(Calculator.evaluateMath("(1+2)*3")) == "9"
                expect(Calculator.evaluateMath("2^10")) == "1024"
            }

            it("keeps a trailing .0 when the input expression contains a decimal point") {
                expect(Calculator.evaluateMath("3.0")) == "3.0"
                expect(Calculator.evaluateMath("2.5*4")) == "10.0"
                expect(Calculator.evaluateMath("1.5+1.5")) == "3.0"
                expect(Calculator.evaluateMath("0.5*2")) == "1.0"
                expect(Calculator.evaluateMath("(1.0+2)*3")) == "9.0"
            }

            it("returns nil for partial / malformed input instead of crashing") {
                // Trailing binary operator
                expect(Calculator.evaluateMath("1+")) == nil
                expect(Calculator.evaluateMath("5*")) == nil
                expect(Calculator.evaluateMath("2.+")) == nil
                expect(Calculator.evaluateMath("4-")) == nil
                // Leading non-unary operator
                expect(Calculator.evaluateMath("*5")) == nil
                expect(Calculator.evaluateMath("/3")) == nil
                // Unbalanced parens
                expect(Calculator.evaluateMath("(5+1")) == nil
                expect(Calculator.evaluateMath("5+1)")) == nil
                expect(Calculator.evaluateMath("()")) == nil
                // Doubled binary ops (excluding "** = ^")
                expect(Calculator.evaluateMath("1+*2")) == nil
                expect(Calculator.evaluateMath("1//2")) == nil
                // Operator next to closing paren
                expect(Calculator.evaluateMath("(1+)")) == nil
                // Empty / whitespace
                expect(Calculator.evaluateMath("")) == nil
                expect(Calculator.evaluateMath("   ")) == nil
                // Implicit multiplication not allowed
                expect(Calculator.evaluateMath("(2)(3)")) == nil
            }

            it("accepts unary minus / plus after a binary op") {
                expect(Calculator.evaluateMath("5*-3")) == "-15"
                expect(Calculator.evaluateMath("5+-3")) == "2"
            }
        }
    }
}
