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
        // Schema 9 introduces parentIdentifier on CPYFolder and CPYSnippet
        // (preparation for nested snippet folders). Folders default to root
        // ("" parentIdentifier). Snippets are backfilled to point at the
        // folder that currently contains them via the legacy `snippets` list.
        var config = Realm.Configuration(schemaVersion: 9, migrationBlock: { migration, oldSchemaVersion in
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
            if oldSchemaVersion <= 8 {
                // Pass 1: walk old folders, gather snippetID -> folderID map.
                var folderMap: [String: [String]] = [:]
                migration.enumerateObjects(ofType: CPYFolder.className()) { oldObject, newObject in
                    guard let oldObject = oldObject, let newObject = newObject else { return }
                    let folderID = (oldObject["identifier"] as? String) ?? ""
                    newObject["parentIdentifier"] = ""
                    let oldSnippets = oldObject["snippets"] as? List<DynamicObject>
                    var snippetIDs: [String] = []
                    oldSnippets?.forEach { oldSnippet in
                        if let sid = oldSnippet["identifier"] as? String { snippetIDs.append(sid) }
                    }
                    folderMap[folderID] = snippetIDs
                }
                let snippetParent = SnippetParentBackfill.parentMap(folders: folderMap)
                // Pass 2: write parentIdentifier into snippets.
                migration.enumerateObjects(ofType: CPYSnippet.className()) { _, newObject in
                    guard let newObject = newObject else { return }
                    let snippetID = (newObject["identifier"] as? String) ?? ""
                    newObject["parentIdentifier"] = SnippetParentBackfill.parentFor(snippetId: snippetID, in: snippetParent)
                }
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

// MARK: - SnippetParentBackfill

/// Pure helper exposed for testing the v8 → v9 backfill of CPYSnippet.parentIdentifier.
enum SnippetParentBackfill {
    /// Inverts a `[folderID: [snippetID]]` mapping into `[snippetID: folderID]`.
    static func parentMap(folders: [String: [String]]) -> [String: String] {
        var out: [String: String] = [:]
        for (folderID, snippetIDs) in folders {
            for snippetID in snippetIDs {
                out[snippetID] = folderID
            }
        }
        return out
    }

    /// Returns the parent folder ID for a snippet, or `""` if it is not in any folder.
    static func parentFor(snippetId: String, in map: [String: String]) -> String {
        return map[snippetId] ?? ""
    }
}
