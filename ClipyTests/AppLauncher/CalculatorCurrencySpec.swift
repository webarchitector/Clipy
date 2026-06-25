import Quick
import Nimble
import Foundation
@testable import Clipy

class CalculatorCurrencySpec: QuickSpec {
    override class func spec() {

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
                expect(Calculator.parseCurrency("nonsense")) == nil
                expect(Calculator.parseCurrency("15 thb")) == nil
                expect(Calculator.parseCurrency("usd thb")) == nil
            }

            it("rejects malformed input that should never reach the API") {
                expect(Calculator.parseCurrency("")) == nil
                expect(Calculator.parseCurrency("   ")) == nil
                expect(Calculator.parseCurrency("15")) == nil                  // amount only
                expect(Calculator.parseCurrency("usd")) == nil                 // currency only
                expect(Calculator.parseCurrency("15 usd")) == nil              // missing target
                expect(Calculator.parseCurrency("15.5.5 usd thb")) == nil      // double-dot amount
                expect(Calculator.parseCurrency("-15 usd thb")) == nil         // negative amounts not in regex
                expect(Calculator.parseCurrency("15 us thb")) == nil           // 2-letter codes rejected (need 3-4)
                expect(Calculator.parseCurrency("15 usddd thb")) == nil        // 5-letter code rejected
                expect(Calculator.parseCurrency("15 usd1 thb")) == nil         // digit in code
                expect(Calculator.parseCurrency("15 руб usd")) == nil          // cyrillic in code
                expect(Calculator.parseCurrency("15 usd 🇺🇸")) == nil          // emoji
                expect(Calculator.parseCurrency("usd 15 thb")) == nil          // wrong order
            }

            it("trims surrounding whitespace") {
                let result = Calculator.parseCurrency("  15  usd  thb  ")
                expect(result?.amount) == 15.0
                expect(result?.from) == "usd"
                expect(result?.to) == "thb"
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

            it("does not crash on NaN / infinity / very small / very large") {
                // formatRate uses truncatingRemainder which handles NaN/Inf —
                // these used to crash older versions and we want to lock in
                // the contract: it returns *something* and doesn't trap.
                _ = Calculator.formatRate(.nan)
                _ = Calculator.formatRate(.infinity)
                _ = Calculator.formatRate(-.infinity)
                _ = Calculator.formatRate(1e-30)
                _ = Calculator.formatRate(1e30)
                _ = Calculator.formatRate(0)
                _ = Calculator.formatRate(-0)
                expect(Calculator.formatRate(0)) == "0"
            }

            it("handles very small fractional values") {
                expect(Calculator.formatRate(0.000001)) == "1e-06"
            }
        }
    }
}
