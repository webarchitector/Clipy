import Quick
import Nimble
import Cocoa
@testable import Clipy

class CPYClipDataPreferredTitleSpec: QuickSpec {
    override class func spec() {
        describe("CPYClipData.preferredTitle") {

            it("prefers a non-empty trimmed string value") {
                let data = CPYClipData(image: NSImage())
                data.types = [.string]
                data.stringValue = "  hello  "
                expect(data.preferredTitle) == "hello"
            }

            it("ignores whitespace-only stringValue and falls through") {
                let data = CPYClipData(image: NSImage())
                data.types = [.fileURL]
                data.stringValue = "   "
                data.fileNames = ["/tmp/image.png"]
                expect(data.preferredTitle) == "image.png"
            }

            it("falls back to the first file's display name when stringValue is empty") {
                let data = CPYClipData(image: NSImage())
                data.types = [.fileURL]
                data.stringValue = ""
                data.fileNames = ["/tmp/some.txt", "/tmp/other.txt"]
                expect(data.preferredTitle) == "some.txt"
            }

            it("falls back to URL.lastPathComponent when neither string nor files are set") {
                let data = CPYClipData(image: NSImage())
                data.types = [.URL]
                data.URLs = ["https://example.com/path/to/page.html"]
                expect(data.preferredTitle) == "page.html"
            }

            it("falls back to URL host when there's no path component") {
                let data = CPYClipData(image: NSImage())
                data.types = [.URL]
                data.URLs = ["https://example.com"]
                expect(data.preferredTitle) == "example.com"
            }

            it("falls back to the raw URL string when URL parsing degrades") {
                let data = CPYClipData(image: NSImage())
                data.types = [.URL]
                data.URLs = ["not a real url"]
                expect(data.preferredTitle) == "not a real url"
            }

            it("returns (Image) for image-only clips with nothing else to display") {
                let data = CPYClipData(image: NSImage())
                data.types = [.tiff]
                expect(data.preferredTitle) == "(Image)"
            }

            it("returns (PDF) for PDF-only clips") {
                let data = CPYClipData(image: NSImage())
                data.types = [.pdf]
                data.PDF = Data()
                expect(data.preferredTitle) == "(PDF)"
            }

            it("returns empty string for unknown-type empty clips") {
                let data = CPYClipData(image: NSImage())
                data.types = [.html]
                expect(data.preferredTitle) == ""
            }
        }
    }
}
