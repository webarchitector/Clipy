//
//  Realm+Migration.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/10/16.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import RealmSwift

extension Realm {
    static func migration() {
        // Schema 8 added CPYClip.isPinned and CPYClip.sourceBundleID. Both
        // default to false / "" so no per-object migration is needed; just
        // a version bump tells Realm the new schema is intentional.
        var config = Realm.Configuration(schemaVersion: 8, migrationBlock: { migration, oldSchemaVersion in
            if oldSchemaVersion <= 2 {
                // Add identifier in CPYSnippet
                migration.enumerateObjects(ofType: CPYSnippet.className()) { _, newObject in
                    guard let newObject = newObject else { return }
                    newObject["identifier"] = UUID().uuidString
                }
            }
            if oldSchemaVersion <= 4 {
                // Add identifier in CPYFolder
                migration.enumerateObjects(ofType: CPYFolder.className()) { _, newObject in
                    guard let newObject = newObject else { return }
                    newObject["identifier"] = UUID().uuidString
                }
            }
            if oldSchemaVersion <= 5 {
                // Update RealmObjc to RealmSwift
                migration.enumerateObjects(ofType: CPYClip.className(), { oldObject, newObject in
                    guard let oldObject = oldObject, let newObject = newObject else { return }
                    newObject["dataPath"] = oldObject["dataPath"]
                    newObject["title"] = oldObject["title"]
                    newObject["dataHash"] = oldObject["dataHash"]
                    newObject["primaryType"] = oldObject["primaryType"]
                    newObject["updateTime"] = oldObject["updateTime"]
                    newObject["thumbnailPath"] = oldObject["thumbnailPath"]
                })
                migration.enumerateObjects(ofType: CPYSnippet.className(), { oldObject, newObject in
                    guard let oldObject = oldObject, let newObject = newObject else { return }
                    newObject["index"] = oldObject["index"]
                    newObject["enable"] = oldObject["enable"]
                    newObject["title"] = oldObject["title"]
                    newObject["content"] = oldObject["content"]
                    if oldSchemaVersion >= 3 {
                        newObject["identifier"] = oldObject["identifier"]
                    }
                })
                migration.enumerateObjects(ofType: CPYFolder.className(), { oldObject, newObject in
                    guard let oldObject = oldObject, let newObject = newObject else { return }
                    newObject["index"] = oldObject["index"]
                    newObject["enable"] = oldObject["enable"]
                    newObject["title"] = oldObject["title"]
                    if oldSchemaVersion >= 5 {
                        newObject["identifier"] = oldObject["identifier"]
                    }
                })
            }
        })
        // Compact the realm file when at least 100 MB on disk and less than 50% used.
        config.shouldCompactOnLaunch = { totalBytes, usedBytes in
            let oneHundredMB = 100 * 1024 * 1024
            return totalBytes > oneHundredMB && Double(usedBytes) / Double(totalBytes) < 0.5
        }
        Realm.Configuration.defaultConfiguration = config
        _ = try? Realm()
    }
}
