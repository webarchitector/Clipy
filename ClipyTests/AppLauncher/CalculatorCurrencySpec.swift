import Quick
import Nimble
@testable import Clipy

class CalculatorCurrencySpec: QuickSpec {
    override func spec() {

        describe("Calculator.parseCurrency") {

            it("parses simple integer amounts") {
                let result = Calculator.parseCurrency("15 usd thb")
                expect(result?.amount) == 15.0
                expect(result?.from) == "usd"
                expect(result?.to) == "thb"
            }

            it("parses decimal amounts") {
                let result = Calculator.parseCurrency("15.5 usd thb")
                expect(result?.amount) == 15.5
            }

            it("normalizes currency codes to lowercase") {
                let result = Calculator.parseCurrency("15 USD THB")
                expect(result?.from) == "usd"
                expect(result?.to) == "thb"
            }

            it("accepts 4-letter codes (e.g. usdt)") {
                let result = Calculator.parseCurrency("1 usdt thb")
                expect(result?.from) == "usdt"
            }

            it("rejects nonsense") {
                expect(Calculator.parseCurrency("nonsense")).to(beNil())
                expect(Calculator.parseCurrency("15 thb")).to(beNil())
                expect(Calculator.parseCurrency("usd thb")).to(beNil())
            }
        }

        describe("Calculator.formatRate") {

            it("strips the decimal for integer values") {
                expect(Calculator.formatRate(15.0)) == "15"
            }

            it("uses %g for non-integer values") {
                expect(Calculator.formatRate(15.5)) == "15.5"
                expect(Calculator.formatRate(0.001)) == "0.001"
            }
        }
    }
}
