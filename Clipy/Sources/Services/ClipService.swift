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
import Combine
import RealmSwift

final class ClipService {

    // MARK: - Properties
    fileprivate var cachedChangeCount = CurrentValueSubject<Int, Never>(0)
    fileprivate var storeTypes = [String: NSNumber]()
    fileprivate var isCopySameHistory = false
    fileprivate var isOverwriteSameHistory = false
    fileprivate var cachedThumbnailWidth = 0
    fileprivate var cachedThumbnailHeight = 0
    fileprivate let queue = DispatchQueue(label: "com.clipy-app.Clipy.ClipService", qos: .utility)
    fileprivate let lock = NSRecursiveLock(name: "com.clipy-app.Clipy.ClipUpdatable")
    fileprivate var cancellables: Set<AnyCancellable> = []
    fileprivate var recentContentHashes = [String]()
    fileprivate let maxRecentHashes = 5
    fileprivate var eventMonitor: Any?
    fileprivate let checkSubject = PassthroughSubject<Void, Never>()
    fileprivate let realmWriteQueue = DispatchQueue(label: "com.clipy-app.Clipy.RealmWrite", qos: .utility)

    // MARK: - Clips
    func startMonitoring() {
        cancellables.removeAll()
        stopEventMonitor()
        cachedChangeCount.send(NSPasteboard.general.changeCount)

        // Event-driven: global key monitor for Cmd+C / Cmd+X (zero wake-ups)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }
            // C = 8, X = 7 (virtual key codes)
            if event.keyCode == 8 || event.keyCode == 7 {
                self?.checkSubject.send(())
            }
        }

        // Slow fallback poll for programmatic copies (apps that copy without Cmd+C)
        let slowPoll = Timer.publish(every: 15, on: .main, in: .default)
            .autoconnect()
            .map { _ in () }
            .eraseToAnyPublisher()

        // Merge event-driven checks with slow poll, then check changeCount
        checkSubject
            .delay(for: .milliseconds(100), scheduler: queue)
            .merge(with: slowPoll)
            .receive(on: queue)
            .map { NSPasteboard.general.changeCount }
            .filter { [weak self] count in
                guard let self = self else { return false }
                return count != self.cachedChangeCount.value
            }
            .sink { [weak self] count in
                self?.cachedChangeCount.send(count)
                self?.create()
            }
            .store(in: &cancellables)

        // Store types
        let defaults = AppEnvironment.current.defaults
        defaults.dictionaryPublisher(forKey: Constants.UserDefaults.storeTypes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] types in
                guard let self = self else { return }
                self.lock.lock(); self.storeTypes = types; self.lock.unlock()
            }
            .store(in: &cancellables)

        // Cached settings used in save() — avoid UserDefaults reads on every clip.
        // Initial values are seeded synchronously here so save() sees correct
        // state even before Combine emits the first prepended value.
        lock.lock()
        isCopySameHistory = defaults.bool(forKey: Constants.UserDefaults.copySameHistory)
        isOverwriteSameHistory = defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory)
        cachedThumbnailWidth = defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth)
        cachedThumbnailHeight = defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight)
        lock.unlock()

        defaults.boolPublisher(forKey: Constants.UserDefaults.copySameHistory)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self = self else { return }
                self.lock.lock(); self.isCopySameHistory = value; self.lock.unlock()
            }
            .store(in: &cancellables)
        defaults.boolPublisher(forKey: Constants.UserDefaults.overwriteSameHistory)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self = self else { return }
                self.lock.lock(); self.isOverwriteSameHistory = value; self.lock.unlock()
            }
            .store(in: &cancellables)
        defaults.integerPublisher(forKey: Constants.UserDefaults.thumbnailWidth)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self = self else { return }
                self.lock.lock(); self.cachedThumbnailWidth = value; self.lock.unlock()
            }
            .store(in: &cancellables)
        defaults.integerPublisher(forKey: Constants.UserDefaults.thumbnailHeight)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self = self else { return }
                self.lock.lock(); self.cachedThumbnailHeight = value; self.lock.unlock()
            }
            .store(in: &cancellables)
    }

    func stopMonitoring() {
        cancellables.removeAll()
        stopEventMonitor()
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
            .forEach { ThumbnailCache.shared.removeObject(forKey: $0) }
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
            ThumbnailCache.shared.removeObject(forKey: path)
        }
        // Delete Realm
        realm.transaction { realm.delete(clip) }
    }

    func incrementChangeCount() {
        // Serialize through `queue` so the read-modify-write doesn't race with
        // the filter/sink in startMonitoring(), which also runs on `queue`.
        queue.async { [weak self] in
            guard let self = self else { return }
            self.cachedChangeCount.send(self.cachedChangeCount.value + 1)
        }
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
        if string.isEmpty { return false }
        let upper = CharacterSet.uppercaseLetters
        let lower = CharacterSet.lowercaseLetters
        let digit = CharacterSet.decimalDigits
        let alnum = CharacterSet.alphanumerics
        var hasUpper = false, hasLower = false, hasDigit = false, hasSpecial = false
        var count = 0
        for scalar in string.unicodeScalars {
            count += 1
            if count > 128 { return false }
            if scalar == " " { return false }
            if !hasUpper && upper.contains(scalar) { hasUpper = true; continue }
            if !hasLower && lower.contains(scalar) { hasLower = true; continue }
            if !hasDigit && digit.contains(scalar) { hasDigit = true; continue }
            if !hasSpecial && !alnum.contains(scalar) { hasSpecial = true }
        }
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

        // Skip if identical to any of the last 5 clips
        if recentContentHashes.contains(contentHash) { return }

        // Copy already copied history / invalidated clip — single Realm lookup
        if let existing = realm.object(ofType: CPYClip.self, forPrimaryKey: contentHash),
           !isCopySameHistory || existing.isInvalidated {
            return
        }

        // Don't save empty string history
        if data.isOnlyStringType && data.stringValue.isEmpty { return }

        // Overwrite same history
        let savedHash = isOverwriteSameHistory ? contentHash : UUID().uuidString

        recentContentHashes.append(contentHash)
        if recentContentHashes.count > maxRecentHashes {
            recentContentHashes.removeFirst()
        }

        // Cap the stored image to 4K on the long side. Dedup hash above already
        // committed to the *original* content, so this only affects what gets
        // archived to disk and reconstituted on paste.
        data.image = CPYClipData.cappedForStorage(data.image)

        // Capture immutable values before dispatch
        let unixTime = Int(Date().timeIntervalSince1970)
        let savedPath = CPYUtilities.applicationSupportFolder() + "/\(UUID().uuidString).data"
        let title = data.preferredTitle[0...10000]
        let primaryType = data.primaryType?.rawValue ?? ""

        // Extract thumbnail/color images on the calling thread so we can
        // release the heavy CPYClipData (with RTF, PDF, full image) early.
        let thumbnailImage = data.thumbnailImage(width: cachedThumbnailWidth,
                                                 height: cachedThumbnailHeight)
        let colorCodeImage = data.colorCodeImage

        let writeQueue = realmWriteQueue
        DispatchQueue.global(qos: .userInitiated).async { [data] in
            var thumbnailPath = ""
            var isColorCode = false
            if let thumbnailImage = thumbnailImage {
                ThumbnailCache.shared.setObjectAsync(thumbnailImage, forKey: "\(unixTime)")
                thumbnailPath = "\(unixTime)"
            }
            if let colorCodeImage = colorCodeImage {
                ThumbnailCache.shared.setObjectAsync(colorCodeImage, forKey: "\(unixTime)")
                thumbnailPath = "\(unixTime)"
                isColorCode = true
            }
            // Save .data file and release the heavy CPYClipData immediately after
            guard CPYUtilities.prepareSaveToPath(CPYUtilities.applicationSupportFolder()) else { return }
            let archived = autoreleasepool { LegacyKeyedArchive.archiveRootObject(data, toFile: savedPath) }
            guard archived else { return }
            // Persist on a dedicated background queue so writes don't block main.
            writeQueue.async {
                let clip = CPYClip()
                clip.dataPath = savedPath
                clip.title = title
                clip.dataHash = savedHash
                clip.updateTime = unixTime
                clip.primaryType = primaryType
                clip.thumbnailPath = thumbnailPath
                clip.isColorCode = isColorCode
                guard let writeRealm = Realm.safeInstance() else { return }
                writeRealm.transaction { writeRealm.add(clip, update: .all) }
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
