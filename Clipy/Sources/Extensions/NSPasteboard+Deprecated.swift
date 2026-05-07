//
//  NSPasteboard+Deprecated.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2017/12/30.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

/// Legacy pasteboard type names from the pre-Swift-4 era ("NSStringPboardType" etc.).
/// They remain in use because clips persisted before the modern UTI-based names
/// (`.string`, `.tiff`, `.fileURL` …) carry these raw strings in their archived
/// `CPYClipData.types`, and unarchiving + matching still has to recognise them.
/// Modern code should always read AND write the modern equivalents — the
/// deprecated names are only ever consumed when reading legacy data or when
/// matching against a pasteboard that still posts the old keys (some apps do).
///
/// Sunset path: drop a deprecated alias only after a Realm migration that
/// rewrites every clip's `types` array; until then they stay.
extension NSPasteboard.PasteboardType {

    static var deprecatedString: NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(rawValue: "NSStringPboardType")
    }

    static var deprecatedRTF: NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(rawValue: "NSRTFPboardType")
    }

    static var deprecatedRTFD: NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(rawValue: "NSRTFDPboardType")
    }

    static var deprecatedPDF: NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(rawValue: "NSPDFPboardType")
    }

    static var deprecatedFilenames: NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")
    }

    static var deprecatedURL: NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")
    }

    static var deprecatedTIFF: NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(rawValue: "NSTIFFPboardType")
    }

}
