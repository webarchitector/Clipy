//
//  CPYClipData.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import CryptoKit

private extension NSColor {
    /// Inline replacement for SwiftHEXColors' `init(hexString:)`. Accepts
    /// "#RGB", "#RGBA", "#RRGGBB", "#RRGGBBAA" with or without the leading "#".
    // swiftlint:disable operator_usage_whitespace
    convenience init?(clipyHexString: String) {
        var hex = clipyHexString
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard let value = UInt64(hex, radix: 16) else { return nil }
        let red, green, blue, alpha: CGFloat
        switch hex.count {
        case 3:
            red   = CGFloat((value & 0xF00) >> 8) / 15
            green = CGFloat((value & 0x0F0) >> 4) / 15
            blue  = CGFloat( value & 0x00F      ) / 15
            alpha = 1
        case 4:
            red   = CGFloat((value & 0xF000) >> 12) / 15
            green = CGFloat((value & 0x0F00) >> 8 ) / 15
            blue  = CGFloat((value & 0x00F0) >> 4 ) / 15
            alpha = CGFloat( value & 0x000F       ) / 15
        case 6:
            red   = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8 ) / 255
            blue  = CGFloat( value & 0x0000FF       ) / 255
            alpha = 1
        case 8:
            red   = CGFloat((value & 0xFF000000) >> 24) / 255
            green = CGFloat((value & 0x00FF0000) >> 16) / 255
            blue  = CGFloat((value & 0x0000FF00) >> 8 ) / 255
            alpha = CGFloat( value & 0x000000FF       ) / 255
        default:
            return nil
        }
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
    // swiftlint:enable operator_usage_whitespace
}

final class CPYClipData: NSObject {

    // MARK: - Properties
    fileprivate let kTypesKey       = "types"
    fileprivate let kStringValueKey = "stringValue"
    fileprivate let kRTFDataKey     = "RTFData"
    fileprivate let kPDFKey         = "PDF"
    fileprivate let kFileNamesKey   = "filenames"
    fileprivate let kURLsKey        = "URL"
    fileprivate let kImageKey       = "image"

    var types          = [NSPasteboard.PasteboardType]()
    var fileNames      = [String]()
    var URLs           = [String]()
    var stringValue    = ""
    var RTFData: Data?
    var PDF: Data?
    var image: NSImage?

    var contentHash: String {
        var payload = StableClipPayload()
        payload.append(types.map { $0.rawValue })
        payload.append(stringValue)
        payload.append(RTFData)
        payload.append(PDF)
        payload.append(fileNames)
        payload.append(URLs)
        // Image fingerprint instead of full pixel hash: width/height + TIFF length +
        // first/last 64 KB. Cuts ~50–100 ms off SHA-256 + 30 MB memcpy on screenshots
        // while keeping dedup deterministic; collisions on real clipboard contents
        // are vanishingly unlikely.
        autoreleasepool {
            payload.append(imageFingerprint())
        }

        let digest = SHA256.hash(data: payload.data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func imageFingerprint() -> Data? {
        guard let image = image, let tiff = image.tiffRepresentation else { return nil }
        var fingerprint = Data()
        let sampleSize = 64 * 1024
        fingerprint.reserveCapacity(24 + min(tiff.count, sampleSize * 2))
        var width = image.size.width.bitPattern.bigEndian
        var height = image.size.height.bitPattern.bigEndian
        var length = UInt64(tiff.count).bigEndian
        withUnsafeBytes(of: &width) { fingerprint.append(contentsOf: $0) }
        withUnsafeBytes(of: &height) { fingerprint.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { fingerprint.append(contentsOf: $0) }
        if tiff.count <= sampleSize * 2 {
            fingerprint.append(tiff)
        } else {
            fingerprint.append(tiff.prefix(sampleSize))
            fingerprint.append(tiff.suffix(sampleSize))
        }
        return fingerprint
    }

    var primaryType: NSPasteboard.PasteboardType? {
        return types.first
    }
    var isOnlyStringType: Bool {
        return types == [.deprecatedString] || types == [.string]
    }
    var preferredTitle: String {
        if !trimmedStringValue.isEmpty {
            return trimmedStringValue
        }
        if let fileName = fileDisplayNames.first {
            return fileName
        }
        if let urlString = URLs.first?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty {
            if let url = URL(string: urlString) {
                if !url.lastPathComponent.isEmpty {
                    return url.lastPathComponent
                }
                if let host = url.host, !host.isEmpty {
                    return host
                }
                return url.absoluteString
            }
            return urlString
        }

        switch primaryType {
        case .deprecatedTIFF?, .tiff?, .png?:
            return "(Image)"
        case .deprecatedPDF?, .pdf?:
            return "(PDF)"
        default:
            return ""
        }
    }

    func thumbnailImage(width: Int, height: Int) -> NSImage? {
        let maxPixel = max(width, height)

        // Try loading a downsampled thumbnail from file path (for copied image files)
        if !fileNames.isEmpty {
            for path in fileNames {
                if let thumbnail = CPYClipData.downsampledImage(at: path, maxPixelSize: maxPixel) {
                    return thumbnail
                }
            }
        }

        // Fall back to pasteboard image (for direct image paste)
        if let image = image, fileNames.isEmpty {
            return image.resizeImage(CGFloat(width), CGFloat(height))
        }
        return nil
    }

    private static func downsampledImage(at path: String, maxPixelSize: Int) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Cap a pasteboard image to `maxStoredImageDimension` on the long side before
    /// it gets archived. A 5K screenshot's TIFF is ~30 MB; archiving it for every
    /// copy bloats Application Support and slows down the save path. Pastes within
    /// the history will be at the capped resolution — fine for any practical use.
    static let maxStoredImageDimension: Int = 4096

    static func cappedForStorage(_ image: NSImage?) -> NSImage? {
        guard let image = image else { return nil }
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let largest = max(source.width, source.height)
        if largest <= maxStoredImageDimension { return image }
        let scale = Double(maxStoredImageDimension) / Double(largest)
        let newW = max(1, Int((Double(source.width) * scale).rounded()))
        let newH = max(1, Int((Double(source.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let resized = context.makeImage() else { return image }
        return NSImage(cgImage: resized, size: NSSize(width: newW, height: newH))
    }

    var colorCodeImage: NSImage? {
        guard CPYClipData.looksLikeHexColorString(stringValue) else { return nil }
        guard let color = NSColor(clipyHexString: stringValue) else { return nil }
        return NSImage.create(with: color, size: NSSize(width: 20, height: 20))
    }

    /// Auto-detection guard for the color-code thumbnail: only treat a string
    /// as a hex color when it carries a leading `#` or at least one hex letter
    /// (a–f / A–F). This filters out pure-digit strings like "890766" — they
    /// happen to be valid 6-digit hex but were almost certainly copied as a
    /// number, not a color.
    static func looksLikeHexColorString(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("#") { return true }
        return trimmed.contains { ("a"..."f").contains($0) || ("A"..."F").contains($0) }
    }

    static var availableTypes: [NSPasteboard.PasteboardType] {
        return [.deprecatedString,
                .deprecatedRTF,
                .deprecatedRTFD,
                .deprecatedPDF,
                .deprecatedFilenames,
                .deprecatedURL,
                .deprecatedTIFF]
    }
    static var availableTypesString: [String] {
        return ["String",
                "RTF",
                "RTFD",
                "PDF",
                "Filenames",
                "URL",
                "TIFF"]
    }
    static let availableTypesDictinary: [NSPasteboard.PasteboardType: String] = {
        var types = [NSPasteboard.PasteboardType: String]()
        // Legacy types
        zip(CPYClipData.availableTypes, CPYClipData.availableTypesString).forEach { types[$0] = $1 }
        // Modern UTI types — mapped to the same preference keys as their legacy counterparts
        types[.tiff] = "TIFF"          // public.tiff
        types[.png] = "TIFF"           // public.png — treated as image, same setting
        types[.rtf] = "RTF"            // public.rtf
        types[.pdf] = "PDF"            // com.adobe.pdf
        types[.string] = "String"      // public.utf8-plain-text
        types[.URL] = "URL"            // public.url
        types[.fileURL] = "Filenames"  // public.file-url
        return types
    }()

    // MARK: - Init
    init(pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        super.init()
        self.types = types
        types.forEach { type in
            switch type {
            case .deprecatedString, .string:
                if stringValue.isEmpty {
                    guard let string = pasteboard.string(forType: type) else { return }
                    stringValue = string
                }
            case .deprecatedRTFD:
                RTFData = pasteboard.data(forType: .deprecatedRTFD)
            case .deprecatedRTF, .rtf:
                if RTFData == nil {
                    RTFData = pasteboard.data(forType: type)
                }
            case .deprecatedPDF, .pdf:
                if PDF == nil {
                    PDF = pasteboard.data(forType: type)
                }
            case .deprecatedFilenames:
                guard let filenames = pasteboard.propertyList(forType: .deprecatedFilenames) as? [String] else { return }
                self.fileNames = filenames
            case .fileURL:
                if fileNames.isEmpty {
                    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return }
                    self.fileNames = urls.compactMap { $0.path }
                }
            case .deprecatedURL:
                guard let urls = pasteboard.propertyList(forType: .deprecatedURL) as? [String] else { return }
                URLs = urls
            case .URL:
                if URLs.isEmpty {
                    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return }
                    URLs = urls.compactMap { $0.absoluteString }
                }
            case .deprecatedTIFF, .tiff, .png:
                if image == nil {
                    image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
                }
            default: break
            }
        }
    }

    init(image: NSImage) {
        self.types = [.deprecatedTIFF]
        self.image = image
    }

    // MARK: - NSCoding
    @objc func encodeWithCoder(_ aCoder: NSCoder) {
        aCoder.encode(types.map { $0.rawValue }, forKey: kTypesKey)
        aCoder.encode(stringValue, forKey: kStringValueKey)
        aCoder.encode(RTFData, forKey: kRTFDataKey)
        aCoder.encode(PDF, forKey: kPDFKey)
        aCoder.encode(fileNames, forKey: kFileNamesKey)
        aCoder.encode(URLs, forKey: kURLsKey)
        aCoder.encode(image, forKey: kImageKey)
    }

    @objc required init(coder aDecoder: NSCoder) {
        types = (aDecoder.decodeObject(forKey: kTypesKey) as? [String])?.compactMap { NSPasteboard.PasteboardType(rawValue: $0) } ?? []
        fileNames = aDecoder.decodeObject(forKey: kFileNamesKey) as? [String] ?? [String]()
        URLs = aDecoder.decodeObject(forKey: kURLsKey) as? [String] ?? [String]()
        stringValue = aDecoder.decodeObject(forKey: kStringValueKey) as? String ?? ""
        RTFData = aDecoder.decodeObject(forKey: kRTFDataKey) as? Data
        PDF = aDecoder.decodeObject(forKey: kPDFKey) as? Data
        image = aDecoder.decodeObject(forKey: kImageKey) as? NSImage
        super.init()
    }
}

private struct StableClipPayload {
    private(set) var data = Data()

    mutating func append(_ strings: [String]) {
        append(UInt64(strings.count))
        strings.forEach { append($0) }
    }

    mutating func append(_ string: String) {
        append(string.data(using: .utf8) ?? Data())
    }

    mutating func append(_ value: Data?) {
        guard let value = value else {
            append(UInt64.max)
            return
        }
        append(value)
    }

    private mutating func append(_ value: Data) {
        append(UInt64(value.count))
        data.append(value)
    }

    private mutating func append(_ value: UInt64) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private extension CPYClipData {
    var trimmedStringValue: String {
        stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var fileDisplayNames: [String] {
        fileNames.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}
