//
//  InputSource.swift
//
//  Clipy InputSource — wraps a Carbon TIS keyboard layout/input source so it
//  can be presented in the preferences UI and selected by a hotkey.
//

import Carbon
import Cocoa

final class InputSource {
    let tisInputSource: TISInputSource
    let identifier: String
    let name: String
    let icon: NSImage?

    init?(tisInputSource: TISInputSource) {
        guard let id = tisInputSource.inputSourceID,
              let name = tisInputSource.localizedName else {
            return nil
        }
        self.tisInputSource = tisInputSource
        self.identifier = id
        self.name = name

        var iconImage: NSImage?
        if let imageURL = tisInputSource.iconImageURL {
            for url in [imageURL.retinaImageURL, imageURL.tiffImageURL, imageURL].compactMap({ $0 }) {
                if let image = NSImage(contentsOf: url) {
                    iconImage = image
                    break
                }
            }
            if iconImage == nil {
                iconImage = NSWorkspace.shared.icon(forFile: imageURL.path)
            }
        }
        self.icon = iconImage ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
    }

    func select() {
        TISSelectInputSource(tisInputSource)
        // Carbon TIS workaround: with complex input sources (CJK/Vietnamese
        // IMEs that route through ComponentInstance) the first call sometimes
        // succeeds at the OS level but the active text-input client doesn't
        // pick up the change until a second nudge. Re-fire after 50ms — for
        // plain keyboard layouts the second call is a harmless no-op because
        // the current source already matches.
        let source = tisInputSource
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
               current.inputSourceID == source.inputSourceID {
                return
            }
            TISSelectInputSource(source)
        }
    }
}

extension InputSource: Equatable {
    static func == (lhs: InputSource, rhs: InputSource) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

extension InputSource {
    private static var _sources: [InputSource]?

    /// Cached list of selectable keyboard input sources. Carbon TIS doesn't
    /// fire change notifications when the user adds/removes layouts via
    /// System Settings, so the cache is process-lifetime; users restart the
    /// app to pick up new layouts (matches selector's behaviour).
    static var sources: [InputSource] {
        if let cached = _sources { return cached }
        let result = loadSources()
        _sources = result
        return result
    }

    private static func loadSources() -> [InputSource] {
        let nsArray = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        guard let list = nsArray as? [TISInputSource] else { return [] }
        return list
            .filter { $0.inputSourceCategory == TISInputSource.Category.keyboardInputSource && $0.isSelectable }
            .compactMap { InputSource(tisInputSource: $0) }
    }
}

private extension URL {
    var retinaImageURL: URL? {
        var components = pathComponents
        let filename: String = components.removeLast()
        let ext: String = pathExtension
        let retinaFilename = filename.replacingOccurrences(of: "." + ext, with: "@2x." + ext)
        return NSURL.fileURL(withPathComponents: components + [retinaFilename])
    }

    var tiffImageURL: URL {
        return deletingPathExtension().appendingPathExtension("tiff")
    }
}
