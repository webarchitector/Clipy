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
import SwiftHEXColors

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
        payload.append(image?.tiffRepresentation)

        let digest = SHA256.hash(data: payload.data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
    var searchableText: String {
        let values = [trimmedStringValue, preferredTitle] + fileNames + fileDisplayNames + URLs
        return normalizedValues(values).joined(separator: "\n")
    }
    var toolTipText: String {
        let values = [trimmedStringValue] + fileNames + URLs + [preferredTitle]
        return normalizedValues(values).joined(separator: "\n")
    }
    var thumbnailImage: NSImage? {
        let defaults = UserDefaults.standard
        let width = defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth)
        let height = defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight)
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
    var colorCodeImage: NSImage? {
        guard let color = NSColor(hexString: stringValue) else { return nil }
        return NSImage.create(with: color, size: NSSize(width: 20, height: 20))
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

    deinit {}

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

    func normalizedValues(_ values: [String]) -> [String] {
        var uniqueValues = [String]()
        var seenValues = Set<String>()

        values.forEach { value in
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { return }
            guard seenValues.insert(trimmedValue).inserted else { return }
            uniqueValues.append(trimmedValue)
        }

        return uniqueValues
    }
}
