//
//  DataCleanService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/20.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Combine
import RealmSwift

final class DataCleanService {

    // MARK: - Properties
    fileprivate var cancellables: Set<AnyCancellable> = []
    fileprivate let queue = DispatchQueue(label: "com.clipy-app.Clipy.DataCleanService", qos: .background)

    // MARK: - Monitoring
    func startMonitoring() {
        cancellables.removeAll()
        // Clean datas every 30 minutes
        Timer.publish(every: 60 * 30, on: .main, in: .default)
            .autoconnect()
            .receive(on: queue)
            .sink { [weak self] _ in
                self?.cleanDatas()
            }
            .store(in: &cancellables)
    }

    func stopMonitoring() {
        cancellables.removeAll()
    }

    // MARK: - Delete Data
    func cleanDatas() {
        guard let realm = Realm.safeInstance() else { return }
        let flowHistories = overflowingClips(with: realm)
        flowHistories
            .filter { !$0.isInvalidated && !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { ThumbnailCache.shared.removeObject(forKey: $0) }
        realm.transaction { realm.delete(flowHistories) }
        cleanFiles(with: realm)
    }

    // Visible to tests via `@testable import Clipy`.
    func overflowingClips(with realm: Realm) -> Results<CPYClip> {
        let clips = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)
        let maxHistorySize = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        // Treat ≤ 0 as "no limit" — never prune. The previous branch returned
        // all clips here, which the caller then deleted: a single zero in the
        // Preferences UI would silently wipe the entire history.
        if maxHistorySize <= 0 { return realm.objects(CPYClip.self).filter("FALSEPREDICATE") }
        if clips.count <= maxHistorySize { return realm.objects(CPYClip.self).filter("FALSEPREDICATE") }
        // Delete first clip
        let lastClip = clips[maxHistorySize - 1]
        if lastClip.isInvalidated { return realm.objects(CPYClip.self).filter("FALSEPREDICATE") }

        // Deletion target
        let updateTime = lastClip.updateTime
        let targetClips = realm.objects(CPYClip.self).filter("updateTime < %d", updateTime)

        return targetClips
    }

    private func cleanFiles(with realm: Realm) {
        let fileManager = FileManager.default
        guard let paths = try? fileManager.contentsOfDirectory(atPath: CPYUtilities.applicationSupportFolder()) else { return }

        let allClipPaths = Set(realm.objects(CPYClip.self)
            .filter { !$0.isInvalidated }
            .compactMap { URL(fileURLWithPath: $0.dataPath).lastPathComponent })

        // Delete orphaned files not referenced by any clip
        DispatchQueue.global(qos: .utility).async {
            Set(paths).subtracting(allClipPaths)
                .map { CPYUtilities.applicationSupportFolder() + "/" + $0 }
                .forEach { CPYUtilities.deleteData(at: $0) }
        }
    }
}
