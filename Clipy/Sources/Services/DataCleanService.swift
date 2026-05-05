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
import RxSwift
import RealmSwift

final class DataCleanService {

    // MARK: - Properties
    fileprivate var disposeBag = DisposeBag()
    fileprivate let scheduler = SerialDispatchQueueScheduler(qos: .background)

    // MARK: - Monitoring
    func startMonitoring() {
        disposeBag = DisposeBag()
        // Clean datas every 30 minutes
        Observable<Int>.interval(.seconds(60 * 30), scheduler: scheduler)
            .subscribe(onNext: { [weak self] _ in
                self?.cleanDatas()
            })
            .disposed(by: disposeBag)
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

    private func overflowingClips(with realm: Realm) -> Results<CPYClip> {
        let clips = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)
        let maxHistorySize = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        if maxHistorySize <= 0 { return clips }
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
