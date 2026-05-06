import Quick
import Nimble
@testable import Clipy

class CalculatorMathSpec: QuickSpec {
    override func spec() {
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
                expect(Calculator.evaluateMath("1/0")).to(beNil())
            }

            it("formats integral results without a decimal") {
                expect(Calculator.evaluateMath("3")) == "3"
                expect(Calculator.evaluateMath("3.0")) == "3"
            }
        }
    }
}
