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

/**
 *  The contents of PasteboardType has been changed with swift 4.
 *  However, we will use the swift 3 style to keep compatibility with existing items
 *  Help wanted - If there is a good implementation I would like to replace it.
 **/
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

    // MARK: - Modern UTI equivalents
    // On modern macOS, pasteboard.types returns UTI strings (e.g. "public.tiff")
    // instead of the legacy names (e.g. "NSTIFFPboardType").
    // These aliases use the system-provided PasteboardType constants.
    static var modernTIFF: NSPasteboard.PasteboardType { return .tiff }       // "public.tiff"
    static var modernPNG: NSPasteboard.PasteboardType { return .png }         // "public.png"
    static var modernString: NSPasteboard.PasteboardType { return .string }   // "public.utf8-plain-text"
    static var modernRTF: NSPasteboard.PasteboardType { return .rtf }         // "public.rtf"
    static var modernPDF: NSPasteboard.PasteboardType { return .pdf }         // "com.adobe.pdf"
    static var modernURL: NSPasteboard.PasteboardType { return .URL }         // "public.url"
    static var modernFileURL: NSPasteboard.PasteboardType { return .fileURL } // "public.file-url"

}
