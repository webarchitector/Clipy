//
//  CPYUtilities.swift
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
import KeyHolder
import RealmSwift

final class CPYUtilities {
    private enum InteractiveWindow: String {
        case preferences
        case snippets
        case history
    }

    private static var interactiveWindows = Set<String>()

    static func initSDKs() {
        AppEnvironment.current.defaults.register(defaults: ["NSApplicationCrashOnExceptions": true])
    }

    static func registerUserDefaultKeys() {
        var defaultValues = [String: Any]()

        defaultValues.updateValue(HotKeyService.defaultKeyCombos, forKey: Constants.UserDefaults.hotKeys)
        /* General */
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.loginItem)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.suppressAlertForLoginItem)
        defaultValues.updateValue(NSNumber(value: 30), forKey: Constants.UserDefaults.maxHistorySize)
        defaultValues.updateValue(NSNumber(value: 1), forKey: Constants.UserDefaults.showStatusItem)
        defaultValues.updateValue(AppDelegate.storeTypesDictinary(), forKey: Constants.UserDefaults.storeTypes)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.inputPasteCommand)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.reorderClipsAfterPasting)

        /* Menu */
        defaultValues.updateValue(NSNumber(value: 16), forKey: Constants.UserDefaults.menuIconSize)
        defaultValues.updateValue(NSNumber(value: 20), forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        defaultValues.updateValue(NSNumber(value: 0), forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        defaultValues.updateValue(NSNumber(value: 10), forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.addClearHistoryMenuItem)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.showIconInTheMenu)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.UserDefaults.addNumericKeyEquivalents)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.showImageInTheMenu)
        defaultValues.updateValue(NSNumber(value: 200), forKey: Constants.UserDefaults.maxLengthOfToolTip)
        defaultValues.updateValue(NSNumber(value: 576), forKey: Constants.UserDefaults.thumbnailWidth)
        defaultValues.updateValue(NSNumber(value: 576), forKey: Constants.UserDefaults.thumbnailHeight)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.overwriteSameHistory)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.copySameHistory)
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.UserDefaults.showColorPreviewInTheMenu)

        /* Beta */
        defaultValues.updateValue(NSNumber(value: true), forKey: Constants.Beta.pastePlainText)
        defaultValues.updateValue(NSNumber(value: 0), forKey: Constants.Beta.pastePlainTextModifier)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.Beta.deleteHistory)
        defaultValues.updateValue(NSNumber(value: 0), forKey: Constants.Beta.deleteHistoryModifier)
        defaultValues.updateValue(NSNumber(value: false), forKey: Constants.Beta.pasteAndDeleteHistory)
        defaultValues.updateValue(NSNumber(value: 0), forKey: Constants.Beta.pasteAndDeleteHistoryModifier)

        AppEnvironment.current.defaults.register(defaults: defaultValues)
    }

    static func applicationSupportFolder() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        let basePath: String = paths.first ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: basePath).appendingPathComponent(Constants.Application.name).path
    }

    static func prepareSaveToPath(_ path: String) -> Bool {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false

        if (fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue) == false {
            do {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return false
            }
        }
        return true
    }

    static func deleteData(at path: String) {
        autoreleasepool {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: path) {
                try? fileManager.removeItem(atPath: path)
            }
        }
    }

    static func presentPreferencesWindow(_ window: NSWindow?) {
        presentInteractiveWindow(.preferences, window: window)
    }

    static func presentSnippetsWindow(_ window: NSWindow?) {
        presentInteractiveWindow(.snippets, window: window)
    }

    static func presentHistoryWindow(_ window: NSWindow?) {
        presentInteractiveWindow(.history, window: window)
    }

    static func closePreferencesWindow() {
        closeInteractiveWindow(.preferences)
    }

    static func closeSnippetsWindow() {
        closeInteractiveWindow(.snippets)
    }

    static func closeHistoryWindow() {
        closeInteractiveWindow(.history)
    }

    static func applyAdaptiveAppearance(to view: NSView?) {
        guard let view = view else { return }

        style(view)
        view.subviews.forEach { applyAdaptiveAppearance(to: $0) }
    }
}

private extension CPYUtilities {
    private static func presentInteractiveWindow(_ interactiveWindow: InteractiveWindow, window: NSWindow?) {
        interactiveWindows.insert(interactiveWindow.rawValue)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func closeInteractiveWindow(_ interactiveWindow: InteractiveWindow) {
        interactiveWindows.remove(interactiveWindow.rawValue)

        guard interactiveWindows.isEmpty else { return }

        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
    }

    private static func style(_ view: NSView) {
        switch view {
        case let textField as NSTextField:
            style(textField)
        case let textView as CPYPlaceHolderTextView:
            textView.textColor = .textColor
            textView.insertionPointColor = .textColor
            textView.backgroundColor = .textBackgroundColor
            textView.placeHolderColor = .placeholderTextColor
        case let textView as NSTextView:
            textView.textColor = .textColor
            textView.insertionPointColor = .textColor
            textView.backgroundColor = .textBackgroundColor
        case let scrollView as NSScrollView:
            style(scrollView)
        case let outlineView as NSOutlineView:
            outlineView.backgroundColor = .controlBackgroundColor
            outlineView.gridColor = .separatorColor
        case let tableView as NSTableView:
            tableView.backgroundColor = .controlBackgroundColor
            tableView.gridColor = .separatorColor
        case let recordView as RecordView:
            style(recordView)
        case let button as CPYDesignableButton:
            button.textColor = .labelColor
        case let designableView as CPYDesignableView:
            style(designableView)
        case let splitView as CPYSplitView:
            splitView.separatorColor = .separatorColor
        default:
            break
        }
    }

    private static func style(_ textField: NSTextField) {
        if textField.isEditable {
            textField.textColor = .textColor
            if textField.drawsBackground {
                textField.backgroundColor = .textBackgroundColor
            }
            return
        }

        textField.textColor = textField.isEnabled ? .labelColor : .secondaryLabelColor
    }

    private static func style(_ scrollView: NSScrollView) {
        switch scrollView.documentView {
        case is NSTextView:
            scrollView.drawsBackground = true
            scrollView.backgroundColor = .textBackgroundColor
        case is NSTableView:
            scrollView.drawsBackground = true
            scrollView.backgroundColor = .controlBackgroundColor
        default:
            break
        }
    }

    private static func style(_ recordView: RecordView) {
        recordView.backgroundColor = .textBackgroundColor
        recordView.borderColor = .separatorColor
        recordView.tintColor = .controlAccentColor
    }

    private static func style(_ designableView: CPYDesignableView) {
        if designableView.borderWidth > 0, shouldUseAdaptiveNeutralColor(designableView.borderColor) {
            designableView.borderColor = .separatorColor
        }

        if designableView.bounds.height <= 1 || designableView.bounds.width <= 1 {
            if shouldUseAdaptiveNeutralColor(designableView.backgroundColor) {
                designableView.backgroundColor = .separatorColor
            }
            return
        }

        guard designableView.backgroundColor.alphaComponent > 0 else { return }
        guard shouldUseAdaptiveNeutralColor(designableView.backgroundColor) else { return }
        designableView.backgroundColor = .windowBackgroundColor
    }

    private static func shouldUseAdaptiveNeutralColor(_ color: NSColor) -> Bool {
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else { return false }
        guard rgbColor.alphaComponent > 0 else { return false }

        let maxComponent = max(rgbColor.redComponent, rgbColor.greenComponent, rgbColor.blueComponent)
        let minComponent = min(rgbColor.redComponent, rgbColor.greenComponent, rgbColor.blueComponent)

        return (maxComponent - minComponent) < 0.08
    }
}
