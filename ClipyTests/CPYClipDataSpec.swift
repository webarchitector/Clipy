import Quick
import Nimble
import Cocoa
@testable import Clipy

class CPYClipDataSpec: QuickSpec {
    override class func spec() {

        describe("contentHash fingerprint for image clips") {

            it("produces the same hash for the same image") {
                let image = Self.makeImage(width: 64, height: 64, red: 200, green: 50, blue: 50)
                let first = CPYClipData(image: image)
                let second = CPYClipData(image: image)
                expect(first.contentHash) == second.contentHash
            }

            it("produces different hashes for differently-coloured images of the same size") {
                let red = CPYClipData(image: Self.makeImage(width: 64, height: 64, red: 255, green: 0, blue: 0))
                let blue = CPYClipData(image: Self.makeImage(width: 64, height: 64, red: 0, green: 0, blue: 255))
                expect(red.contentHash) != blue.contentHash
            }

            it("produces different hashes for images of different sizes") {
                let small = CPYClipData(image: Self.makeImage(width: 32, height: 32, red: 200, green: 200, blue: 200))
                let large = CPYClipData(image: Self.makeImage(width: 256, height: 256, red: 200, green: 200, blue: 200))
                expect(small.contentHash) != large.contentHash
            }

            it("hashes string-only data without touching the image fingerprint path") {
                let helloA = CPYClipData(image: NSImage())
                helloA.types = [.string]
                helloA.stringValue = "hello"
                let helloB = CPYClipData(image: NSImage())
                helloB.types = [.string]
                helloB.stringValue = "hello"
                expect(helloA.contentHash) == helloB.contentHash

                let world = CPYClipData(image: NSImage())
                world.types = [.string]
                world.stringValue = "world"
                expect(helloA.contentHash) != world.contentHash
            }
        }

        describe("cappedForStorage") {

            it("returns nil when the input is nil") {
                expect(CPYClipData.cappedForStorage(nil)).to(beNil())
            }

            it("leaves an image at the cap untouched") {
                let cap = CPYClipData.maxStoredImageDimension
                let image = Self.makeImage(width: cap, height: cap, red: 10, green: 10, blue: 10)
                let result = CPYClipData.cappedForStorage(image)
                expect(result).toNot(beNil())
                expect(result?.size.width) == CGFloat(cap)
                expect(result?.size.height) == CGFloat(cap)
            }

            it("leaves a small image untouched") {
                let image = Self.makeImage(width: 200, height: 100, red: 10, green: 10, blue: 10)
                let result = CPYClipData.cappedForStorage(image)
                expect(result?.size.width) == 200
                expect(result?.size.height) == 100
            }

            it("downscales when the long side exceeds the cap (landscape)") {
                let cap = CPYClipData.maxStoredImageDimension
                // 2x cap on width, 1/16 cap on height — verify the long side is the one capped
                let image = Self.makeImage(width: cap * 2, height: cap / 16, red: 10, green: 10, blue: 10)
                let result = CPYClipData.cappedForStorage(image)
                expect(Int(result?.size.width ?? 0)) == cap
                expect(Int(result?.size.height ?? 0)) == cap / 32
            }

            it("downscales when the long side exceeds the cap (portrait)") {
                let cap = CPYClipData.maxStoredImageDimension
                let image = Self.makeImage(width: cap / 16, height: cap * 2, red: 10, green: 10, blue: 10)
                let result = CPYClipData.cappedForStorage(image)
                expect(Int(result?.size.width ?? 0)) == cap / 32
                expect(Int(result?.size.height ?? 0)) == cap
            }
        }
    }

    /// Builds a deterministic solid-colour NSImage from raw RGBA bytes.
    /// `lockFocus`-based drawing pulls in window-server state that's unstable in
    /// CI; building the CGImage from a byte buffer keeps the test hermetic and
    /// lets two calls with the same arguments produce byte-identical TIFFs.
    private static func makeImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> NSImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = red
            pixels[i + 1] = green
            pixels[i + 2] = blue
            pixels[i + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
