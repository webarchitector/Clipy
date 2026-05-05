//
//  PasteService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import RxSwift
import RxCocoa
import Sauce

final class PasteService {

    // MARK: - Properties
    fileprivate let lock = NSRecursiveLock(name: "com.clipy-app.Clipy.Pastable")
    fileprivate let clipDataCache: NSCache<NSString, CPYClipData> = {
        let cache = NSCache<NSString, CPYClipData>()
        cache.countLimit = 30
        return cache
    }()
    fileprivate var disposeBag = DisposeBag()
    // Cached preference values — refreshed via rx.observe to avoid UserDefaults reads on every paste.
    fileprivate var isPastePlainTextEnabled = false
    fileprivate var pastePlainTextModifier = 0
    fileprivate var isDeleteHistoryEnabled = false
    fileprivate var deleteHistoryModifier = 0
    fileprivate var isPasteAndDeleteHistoryEnabled = false
    fileprivate var pasteAndDeleteHistoryModifier = 0
    fileprivate var inputPasteCommandEnabled = true
    fileprivate var isPastePlainText: Bool {
        guard isPastePlainTextEnabled else { return false }
        return isPressedModifier(pastePlainTextModifier)
    }
    fileprivate var isDeleteHistory: Bool {
        guard isDeleteHistoryEnabled else { return false }
        return isPressedModifier(deleteHistoryModifier)
    }
    fileprivate var isPasteAndDeleteHistory: Bool {
        guard isPasteAndDeleteHistoryEnabled else { return false }
        return isPressedModifier(pasteAndDeleteHistoryModifier)
    }

    func startMonitoring() {
        disposeBag = DisposeBag()
        let defaults = AppEnvironment.current.defaults
        isPastePlainTextEnabled = defaults.bool(forKey: Constants.Beta.pastePlainText)
        pastePlainTextModifier = defaults.integer(forKey: Constants.Beta.pastePlainTextModifier)
        isDeleteHistoryEnabled = defaults.bool(forKey: Constants.Beta.deleteHistory)
        deleteHistoryModifier = defaults.integer(forKey: Constants.Beta.deleteHistoryModifier)
        isPasteAndDeleteHistoryEnabled = defaults.bool(forKey: Constants.Beta.pasteAndDeleteHistory)
        pasteAndDeleteHistoryModifier = defaults.integer(forKey: Constants.Beta.pasteAndDeleteHistoryModifier)
        inputPasteCommandEnabled = defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand)

        bindBool(defaults, Constants.Beta.pastePlainText) { [weak self] in self?.isPastePlainTextEnabled = $0 }
        bindInt(defaults, Constants.Beta.pastePlainTextModifier) { [weak self] in self?.pastePlainTextModifier = $0 }
        bindBool(defaults, Constants.Beta.deleteHistory) { [weak self] in self?.isDeleteHistoryEnabled = $0 }
        bindInt(defaults, Constants.Beta.deleteHistoryModifier) { [weak self] in self?.deleteHistoryModifier = $0 }
        bindBool(defaults, Constants.Beta.pasteAndDeleteHistory) { [weak self] in self?.isPasteAndDeleteHistoryEnabled = $0 }
        bindInt(defaults, Constants.Beta.pasteAndDeleteHistoryModifier) { [weak self] in self?.pasteAndDeleteHistoryModifier = $0 }
        bindBool(defaults, Constants.UserDefaults.inputPasteCommand) { [weak self] in self?.inputPasteCommandEnabled = $0 }
    }

    private func bindBool(_ defaults: UserDefaults, _ key: String, _ assign: @escaping (Bool) -> Void) {
        defaults.rx.observe(Bool.self, key)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: assign)
            .disposed(by: disposeBag)
    }

    private func bindInt(_ defaults: UserDefaults, _ key: String, _ assign: @escaping (Int) -> Void) {
        defaults.rx.observe(Int.self, key)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: assign)
            .disposed(by: disposeBag)
    }

    // MARK: - Cache
    func cachedClipData(for clip: CPYClip) -> CPYClipData? {
        let key = clip.dataPath as NSString
        if let cached = clipDataCache.object(forKey: key) {
            return cached
        }
        guard let data = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: clip.dataPath) else { return nil }
        clipDataCache.setObject(data, forKey: key)
        return data
    }

    // MARK: - Modifiers
    private func isPressedModifier(_ flag: Int) -> Bool {
        let flags = NSEvent.modifierFlags
        if flag == 0 && flags.contains(.command) {
            return true
        } else if flag == 1 && flags.contains(.shift) {
            return true
        } else if flag == 2 && flags.contains(.control) {
            return true
        } else if flag == 3 && flags.contains(.option) {
            return true
        }
        return false
    }
}

// MARK: - Copy
extension PasteService {
    func paste(with clip: CPYClip) {
        guard !clip.isInvalidated else { return }

        // Handling modifier actions
        let isPastePlainText = self.isPastePlainText
        let isPasteAndDeleteHistory = self.isPasteAndDeleteHistory
        let isDeleteHistory = self.isDeleteHistory
        guard isPastePlainText || isPasteAndDeleteHistory || isDeleteHistory else {
            copyToPasteboard(with: clip)
            paste()
            return
        }

        guard let data = cachedClipData(for: clip) else { return }

        // Increment change count for don't copy paste item
        if isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.incrementChangeCount()
        }
        // Paste history
        if isPastePlainText {
            copyToPasteboard(with: data.stringValue)
            paste()
        } else if isPasteAndDeleteHistory {
            copyToPasteboard(with: clip)
            paste()
        }
        // Delete clip
        if isDeleteHistory || isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.delete(with: clip)
        }
    }

    func copyToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.deprecatedString], owner: nil)
        pasteboard.setString(string, forType: .deprecatedString)
    }

    func copyToPasteboard(with clip: CPYClip) {
        lock.lock(); defer { lock.unlock() }

        guard let data = cachedClipData(for: clip) else { return }

        if isPastePlainText {
            copyToPasteboard(with: data.stringValue)
            return
        }

        let pasteboard = NSPasteboard.general
        let types = data.types
        // Pre-compute expensive tiffRepresentation once before the loop
        let cachedTIFFData = data.image?.tiffRepresentation
        pasteboard.declareTypes(types, owner: nil)
        types.forEach { type in
            switch type {
            case .deprecatedString, .string:
                let pbString = data.stringValue
                pasteboard.setString(pbString, forType: type)
            case .deprecatedRTFD:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTFD)
            case .deprecatedRTF, .rtf:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: type)
            case .deprecatedPDF, .pdf:
                guard let pdfData = data.PDF, let pdfRep = NSPDFImageRep(data: pdfData) else { return }
                pasteboard.setData(pdfRep.pdfRepresentation, forType: type)
            case .deprecatedFilenames:
                let fileNames = data.fileNames
                pasteboard.setPropertyList(fileNames, forType: .deprecatedFilenames)
            case .fileURL:
                guard let firstPath = data.fileNames.first else { return }
                let url = URL(fileURLWithPath: firstPath)
                pasteboard.setString(url.absoluteString, forType: .fileURL)
            case .deprecatedURL:
                let url = data.URLs
                pasteboard.setPropertyList(url, forType: .deprecatedURL)
            case .URL:
                guard let firstURL = data.URLs.first else { return }
                pasteboard.setString(firstURL, forType: .URL)
            case .deprecatedTIFF, .tiff, .png:
                guard let imageData = cachedTIFFData else { return }
                pasteboard.setData(imageData, forType: type)
            default: break
            }
        }
    }
}

// MARK: - Paste
extension PasteService {
    func paste() {
        guard inputPasteCommandEnabled else { return }
        // Check Accessibility Permission
        guard AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false) else {
            AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
            return
        }

        let vKeyCode = Sauce.shared.keyCode(by: .v)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            // Disable local keyboard events while pasting
            source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
            // Press Command + V
            let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            keyVDown?.flags = .maskCommand
            // Release Command + V
            let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyVUp?.flags = .maskCommand
            // Post Paste Command
            keyVDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyVUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
