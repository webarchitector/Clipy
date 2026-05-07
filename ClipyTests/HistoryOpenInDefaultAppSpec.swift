import Quick
import Nimble
import Cocoa
@testable import Clipy

class HistoryOpenInDefaultAppSpec: QuickSpec {
    override class func spec() {
        describe("CPYClipboardHistoryWindowController.isOpenablePrimaryType") {

            it("accepts file URL clips") {
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.fileURL.rawValue)) == true
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.deprecatedFilenames.rawValue)) == true
            }

            it("accepts image clips (TIFF + PNG, modern + deprecated)") {
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.tiff.rawValue)) == true
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.deprecatedTIFF.rawValue)) == true
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.png.rawValue)) == true
            }

            it("accepts PDF clips (modern + deprecated)") {
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.pdf.rawValue)) == true
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.deprecatedPDF.rawValue)) == true
            }

            it("rejects plain string clips") {
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.string.rawValue)) == false
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.deprecatedString.rawValue)) == false
            }

            it("rejects RTF / RTFD") {
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.rtf.rawValue)) == false
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.deprecatedRTF.rawValue)) == false
                expect(CPYClipboardHistoryWindowController
                    .isOpenablePrimaryType(NSPasteboard.PasteboardType.deprecatedRTFD.rawValue)) == false
            }

            it("rejects empty / unknown types") {
                expect(CPYClipboardHistoryWindowController.isOpenablePrimaryType("")) == false
                expect(CPYClipboardHistoryWindowController.isOpenablePrimaryType("public.unknown-type")) == false
                expect(CPYClipboardHistoryWindowController.isOpenablePrimaryType("garbage")) == false
            }
        }
    }
}
