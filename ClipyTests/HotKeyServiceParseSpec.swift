import Quick
import Nimble
import Foundation
@testable import Clipy

class HotKeyServiceParseSpec: QuickSpec {
    override class func spec() {
        describe("HotKeyService.parse(with:forKey:)") {

            // The legacy v1.0 storage format Clipy migrated *from*: a top-level
            // dictionary keyed by menu name, each entry an inner dictionary
            // with "keyCode" + "modifiers" Ints. Realistic example:
            //   ["MainMenu": ["keyCode": 9, "modifiers": 768]]
            //
            // HotKeyService isn't Sendable, so under Swift 6 strict concurrency
            // we instantiate one per test instead of capturing a shared `var`
            // across Quick's @Sendable `it` closures.

            it("extracts keyCode + modifiers when both are present and Int") {
                let service = HotKeyService()
                let combos: [String: Any] = ["foo": ["keyCode": 9, "modifiers": 768]]
                expect(service.parse(with: combos, forKey: "foo")?.0) == 9
                expect(service.parse(with: combos, forKey: "foo")?.1) == 768
            }

            it("returns nil when the menu key is absent") {
                let service = HotKeyService()
                let combos: [String: Any] = ["foo": ["keyCode": 9, "modifiers": 768]]
                expect(service.parse(with: combos, forKey: "missing")) == nil
            }

            it("returns nil when the inner value isn't a dict") {
                let service = HotKeyService()
                let combos: [String: Any] = ["foo": "garbage"]
                expect(service.parse(with: combos, forKey: "foo")) == nil
            }

            it("returns nil when keyCode is missing") {
                let service = HotKeyService()
                let combos: [String: Any] = ["foo": ["modifiers": 768]]
                expect(service.parse(with: combos, forKey: "foo")) == nil
            }

            it("returns nil when modifiers is missing") {
                let service = HotKeyService()
                let combos: [String: Any] = ["foo": ["keyCode": 9]]
                expect(service.parse(with: combos, forKey: "foo")) == nil
            }

            it("returns nil when keyCode is the wrong type (e.g. NSNumber via NSDictionary edge cases)") {
                let service = HotKeyService()
                let combos: [String: Any] = ["foo": ["keyCode": "9", "modifiers": 768]]
                expect(service.parse(with: combos, forKey: "foo")) == nil
            }

            it("returns nil for an empty input dictionary") {
                let service = HotKeyService()
                expect(service.parse(with: [:], forKey: "foo")) == nil
            }
        }
    }
}
