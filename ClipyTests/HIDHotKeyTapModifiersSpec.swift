import Quick
import Nimble
import Carbon
import Cocoa
@testable import Clipy

class HIDHotKeyTapModifiersSpec: QuickSpec {
    override class func spec() {
        describe("HIDHotKeyTap.carbonModifiers(from:)") {

            it("maps a single Cmd flag to cmdKey") {
                expect(HIDHotKeyTap.carbonModifiers(from: .maskCommand)) == cmdKey
            }

            it("maps a single Option flag to optionKey") {
                expect(HIDHotKeyTap.carbonModifiers(from: .maskAlternate)) == optionKey
            }

            it("maps a single Control flag to controlKey") {
                expect(HIDHotKeyTap.carbonModifiers(from: .maskControl)) == controlKey
            }

            it("maps a single Shift flag to shiftKey") {
                expect(HIDHotKeyTap.carbonModifiers(from: .maskShift)) == shiftKey
            }

            it("ORs combined modifiers") {
                let flags: CGEventFlags = [.maskCommand, .maskShift]
                expect(HIDHotKeyTap.carbonModifiers(from: flags)) == (cmdKey | shiftKey)
            }

            it("returns 0 for the empty flag set") {
                expect(HIDHotKeyTap.carbonModifiers(from: [])) == 0
            }

            it("ignores irrelevant flags (caps lock, alpha shift, etc.)") {
                let flags: CGEventFlags = [.maskAlphaShift, .maskHelp, .maskCommand]
                expect(HIDHotKeyTap.carbonModifiers(from: flags)) == cmdKey
            }
        }
    }
}
