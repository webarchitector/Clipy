//
//  CPYFolder.swift
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
import RealmSwift

final class CPYFolder: Object {

    // MARK: - Properties
    @objc dynamic var index = 0
    @objc dynamic var enable = true
    @objc dynamic var title = ""
    @objc dynamic var identifier = UUID().uuidString
    @objc dynamic var parentIdentifier = ""

    // MARK: Primary Key
    override static func primaryKey() -> String? {
        return "identifier"
    }

}

// MARK: - Copy
extension CPYFolder {
    func deepCopy() -> CPYFolder {
        return CPYFolder(value: self)
    }
}

// MARK: - Add Folder
extension CPYFolder {
    static func create() -> CPYFolder {
        let realm = Realm.safeInstance()
        let folder = CPYFolder()
        folder.title = "untitled folder"
        let lastFolder = realm?.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true).last
        folder.index = lastFolder?.index ?? -1
        folder.index += 1
        return folder
    }

    func merge() {
        guard let realm = Realm.safeInstance() else { return }
        if let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: identifier) {
            folder.realm?.transaction {
                folder.index = index
                folder.enable = enable
                folder.title = title
            }
        } else {
            let copyFolder = CPYFolder(value: self)
            realm.transaction { realm.add(copyFolder, update: .all) }
        }
    }
}

// MARK: - Remove Folder
extension CPYFolder {
    func remove() {
        guard let realm = Realm.safeInstance() else { return }
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: identifier) else { return }
        // Snippet/subfolder cascade is the editor's responsibility now
        // (see deleteFolderRecursively in CPYSnippetsEditorWindowController).
        folder.realm?.transaction { folder.realm?.delete(folder) }
    }
}

// MARK: - Migrate Index
extension CPYFolder {
    static func rearrangesIndex(_ folders: [CPYFolder]) {
        guard let realm = Realm.safeInstance() else { return }
        realm.transaction {
            for (index, folder) in folders.enumerated() {
                if folder.realm == nil { folder.index = index }
                guard let savedFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.identifier) else { continue }
                savedFolder.index = index
            }
        }
    }
}

// MARK: - Tree (parentIdentifier model)
extension CPYFolder {

    /// Returns the primary-key identifier of a tree node (`CPYFolder` or
    /// `CPYSnippet`). Empty string for any other type — caller is expected
    /// to pass children-of-folder objects only.
    static func nodeID(of obj: Object) -> String {
        if let folder = obj as? CPYFolder { return folder.identifier }
        if let snippet = obj as? CPYSnippet { return snippet.identifier }
        return ""
    }

    /// Returns the merged, index-sorted children (`[CPYFolder | CPYSnippet]`)
    /// of the folder identified by `parentIdentifier`. Pass `""` for roots.
    static func children(parentIdentifier: String, in realm: Realm) -> [Object] {
        let folders = realm.objects(CPYFolder.self).filter("parentIdentifier == %@", parentIdentifier)
        let snippets = realm.objects(CPYSnippet.self).filter("parentIdentifier == %@", parentIdentifier)
        var merged: [Object] = []
        for folder in folders { merged.append(folder) }
        for snippet in snippets { merged.append(snippet) }
        merged.sort { lhs, rhs in
            let lhsIndex = (lhs as? CPYFolder)?.index ?? (lhs as? CPYSnippet)?.index ?? 0
            let rhsIndex = (rhs as? CPYFolder)?.index ?? (rhs as? CPYSnippet)?.index ?? 0
            return lhsIndex < rhsIndex
        }
        return merged
    }

    /// Depth of `folder`: 1 for a root folder, N for an N-deep folder.
    static func depth(of folder: CPYFolder, in realm: Realm) -> Int {
        var depth = 1
        var pid = folder.parentIdentifier
        while !pid.isEmpty {
            guard let parent = realm.object(ofType: CPYFolder.self, forPrimaryKey: pid) else { break }
            depth += 1
            pid = parent.parentIdentifier
            if depth > 1024 { break } // guard against pathological data
        }
        return depth
    }

    /// Number of folder levels in the subtree rooted at `folder` (1 = leaf folder
    /// with no subfolders, 2 = folder with one level of subfolders, …).
    static func maxDescendantDepth(of folder: CPYFolder, in realm: Realm) -> Int {
        let subfolders = realm.objects(CPYFolder.self).filter("parentIdentifier == %@", folder.identifier)
        if subfolders.isEmpty { return 1 }
        return 1 + (subfolders.map { maxDescendantDepth(of: $0, in: realm) }.max() ?? 0)
    }

    /// Walks up `candidate.parentIdentifier` chain; returns true iff `ancestor`
    /// appears in that chain. Used for cycle prevention before reparenting a folder.
    static func isDescendant(_ candidate: CPYFolder, of ancestor: CPYFolder, in realm: Realm) -> Bool {
        var pid = candidate.parentIdentifier
        while !pid.isEmpty {
            if pid == ancestor.identifier { return true }
            guard let parent = realm.object(ofType: CPYFolder.self, forPrimaryKey: pid) else { return false }
            pid = parent.parentIdentifier
        }
        return false
    }

    /// Renumber the children of a parent so their `index` fields are 0..n-1
    /// in current sort order. Runs inline if a write transaction is open,
    /// otherwise opens its own.
    static func renumberSiblings(of parentIdentifier: String, in realm: Realm) {
        let kids = children(parentIdentifier: parentIdentifier, in: realm)
        let writeBlock = {
            for (idx, kid) in kids.enumerated() {
                if let folder = kid as? CPYFolder { folder.index = idx }
                else if let snippet = kid as? CPYSnippet { snippet.index = idx }
            }
        }
        if realm.isInWriteTransaction {
            writeBlock()
        } else {
            try? realm.write { writeBlock() }
        }
    }
}
