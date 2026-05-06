//
//  TISInputSource+Additions.swift
//
//  Clipy InputSource — typed Swift accessors for Carbon TIS properties.
//

import Carbon
import Foundation

extension TISInputSource {
    enum Category {
        static let keyboardInputSource: String = kTISCategoryKeyboardInputSource as String
    }

    private func getProperty(_ key: CFString) -> AnyObject? {
        guard let cfType = TISGetInputSourceProperty(self, key) else {
            return nil
        }
        return Unmanaged<AnyObject>.fromOpaque(cfType).takeUnretainedValue()
    }

    var inputSourceID: String? {
        return getProperty(kTISPropertyInputSourceID) as? String
    }

    var localizedName: String? {
        return getProperty(kTISPropertyLocalizedName) as? String
    }

    var inputSourceCategory: String? {
        return getProperty(kTISPropertyInputSourceCategory) as? String
    }

    var isSelectable: Bool {
        return getProperty(kTISPropertyInputSourceIsSelectCapable) as? Bool ?? false
    }

    var iconImageURL: URL? {
        return getProperty(kTISPropertyIconImageURL) as? URL
    }
}
