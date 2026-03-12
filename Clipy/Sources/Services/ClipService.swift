//
//  ClipService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import RealmSwift
import PINCache
import RxSwift
import RxCocoa

final class ClipService {

    // MARK: - Properties
    fileprivate var cachedChangeCount = BehaviorRelay<Int>(value: 0)
    fileprivate var storeTypes = [String: NSNumber]()
    fileprivate let scheduler = SerialDispatchQueueScheduler(qos: .utility)
    fileprivate let lock = NSRecursiveLock(name: "com.clipy-app.Clipy.ClipUpdatable")
    fileprivate var disposeBag = DisposeBag()
    fileprivate var lastContentHash: String?
    fileprivate var eventMonitor: Any?
    fileprivate let checkSubject = PublishSubject<Void>()

    // MARK: - Clips
    func startMonitoring() {
        disposeBag = DisposeBag()
        stopEventMonitor()
        cachedChangeCount.accept(NSPasteboard.general.changeCount)

        // Event-driven: global key monitor for Cmd+C / Cmd+X (zero wake-ups)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }
            // C = 8, X = 7 (virtual key codes)
            if event.keyCode == 8 || event.keyCode == 7 {
                self?.checkSubject.onNext(())
            }
        }

        // Slow fallback poll for programmatic copies (apps that copy without Cmd+C)
        let slowPoll = Observable<Int>.interval(.seconds(5), scheduler: scheduler).map { _ in }

        // Merge event-driven checks with slow poll, then check changeCount
        Observable.merge(
            checkSubject.asObservable()
                .delay(.milliseconds(100), scheduler: scheduler),
            slowPoll
        )
            .map { NSPasteboard.general.changeCount }
            .withLatestFrom(cachedChangeCount.asObservable()) { ($0, $1) }
            .filter { $0 != $1 }
            .subscribe(onNext: { [weak self] changeCount, _ in
                self?.cachedChangeCount.accept(changeCount)
                self?.create()
            })
            .disposed(by: disposeBag)

        // Store types
        AppEnvironment.current.defaults.rx
            .observe([String: NSNumber].self, Constants.UserDefaults.storeTypes)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                self.storeTypes = $0
                self.lock.unlock()
            })
            .disposed(by: disposeBag)
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func clearAll() {
        guard let realm = Realm.safeInstance() else { return }
        let clips = realm.objects(CPYClip.self)

        // Delete saved images
        clips
            .filter { !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        // Delete Realm
        realm.transaction { realm.delete(clips) }
        // Delete writed datas
        AppEnvironment.current.dataCleanService.cleanDatas()
    }

    func delete(with clip: CPYClip) {
        guard let realm = Realm.safeInstance() else { return }
        // Delete saved images
        let path = clip.thumbnailPath
        if !path.isEmpty {
            PINCache.shared.removeObject(forKey: path)
        }
        // Delete Realm
        realm.transaction { realm.delete(clip) }
    }

    func incrementChangeCount() {
        cachedChangeCount.accept(cachedChangeCount.value + 1)
    }

}

// MARK: - Create Clip
extension ClipService {
    // SwiftLint misidentifies a plain guard in this method as empty enum arguments.
    // swiftlint:disable empty_enum_arguments
    fileprivate func create() {
        lock.lock(); defer { lock.unlock() }

        // Store types
        if !storeTypes.values.contains(NSNumber(value: true)) { return }
        // Pasteboard types
        let pasteboard = NSPasteboard.general
        let types = self.types(with: pasteboard)
        if types.isEmpty { return }

        // Concealed (password managers, Apple Passwords, etc.)
        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        if pasteboard.types?.contains(concealedType) == true { return }

        // Excluded application
        guard !AppEnvironment.current.excludeAppService.frontProcessIsExcludedApplication() else { return }
        // Special applications
        guard !AppEnvironment.current.excludeAppService.copiedProcessIsExcludedApplications(pasteboard: pasteboard) else { return }

        // Skip strings that look like passwords (mixed case + digits + special chars, no spaces)
        if let string = pasteboard.string(forType: .string), Self.looksLikePassword(string) { return }

        // Create data
        let data = CPYClipData(pasteboard: pasteboard, types: types)
        save(with: data)
    }
    // swiftlint:enable empty_enum_arguments

    private static func looksLikePassword(_ string: String) -> Bool {
        guard !string.isEmpty && string.count <= 128 else { return false }
        guard !string.contains(" ") else { return false }
        let hasUpper = string.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLower = string.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasDigit = string.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecial = string.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
        return hasUpper && hasLower && hasDigit && hasSpecial
    }

    func create(with image: NSImage) {
        lock.lock(); defer { lock.unlock() }

        // Create only image data
        let data = CPYClipData(image: image)
        save(with: data)
    }

    fileprivate func save(with data: CPYClipData) {
        guard let realm = Realm.safeInstance() else { return }
        let contentHash = data.contentHash

        // Skip if identical to the most recent clip
        if contentHash == lastContentHash { return }

        // Copy already copied history
        let isCopySameHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.copySameHistory)
        if realm.object(ofType: CPYClip.self, forPrimaryKey: contentHash) != nil, !isCopySameHistory { return }
        // Don't save invalidated clip
        if let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: contentHash), clip.isInvalidated { return }

        // Don't save empty string history
        if data.isOnlyStringType && data.stringValue.isEmpty { return }

        // Overwrite same history
        let isOverwriteHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory)
        let savedHash = isOverwriteHistory ? contentHash : UUID().uuidString

        lastContentHash = contentHash

        // Capture immutable values before dispatch
        let unixTime = Int(Date().timeIntervalSince1970)
        let savedPath = CPYUtilities.applicationSupportFolder() + "/\(UUID().uuidString).data"
        let title = data.preferredTitle[0...10000]
        let primaryType = data.primaryType?.rawValue ?? ""

        // Extract thumbnail/color images on the calling thread so we can
        // release the heavy CPYClipData (with RTF, PDF, full image) early.
        let thumbnailImage = data.thumbnailImage
        let colorCodeImage = data.colorCodeImage

        DispatchQueue.global(qos: .userInitiated).async { [data] in
            var thumbnailPath = ""
            var isColorCode = false
            if let thumbnailImage = thumbnailImage {
                PINCache.shared.setObjectAsync(thumbnailImage, forKey: "\(unixTime)", completion: nil)
                thumbnailPath = "\(unixTime)"
            }
            if let colorCodeImage = colorCodeImage {
                PINCache.shared.setObjectAsync(colorCodeImage, forKey: "\(unixTime)", completion: nil)
                thumbnailPath = "\(unixTime)"
                isColorCode = true
            }
            // Save .data file and release the heavy CPYClipData immediately after
            guard CPYUtilities.prepareSaveToPath(CPYUtilities.applicationSupportFolder()) else { return }
            let archived = autoreleasepool { LegacyKeyedArchive.archiveRootObject(data, toFile: savedPath) }
            guard archived else { return }
            // Build CPYClip entirely on main thread (data is no longer referenced)
            DispatchQueue.main.async {
                let clip = CPYClip()
                clip.dataPath = savedPath
                clip.title = title
                clip.dataHash = savedHash
                clip.updateTime = unixTime
                clip.primaryType = primaryType
                clip.thumbnailPath = thumbnailPath
                clip.isColorCode = isColorCode
                guard let dispatchRealm = Realm.safeInstance() else { return }
                dispatchRealm.transaction { dispatchRealm.add(clip, update: .all) }
            }
        }
    }

    private func types(with pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var seen = Set<NSPasteboard.PasteboardType>()
        return pasteboard.types?.filter { canSave(with: $0) && seen.insert($0).inserted } ?? []
    }

    private func canSave(with type: NSPasteboard.PasteboardType) -> Bool {
        let dictionary = CPYClipData.availableTypesDictinary
        guard let value = dictionary[type] else { return false }
        guard let number = storeTypes[value] else { return false }
        return number.boolValue
    }
}
