# Nested Snippets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Clipy's two-level snippet hierarchy (folder → snippets) with a tree of folders up to 5 levels deep, where each folder may contain snippets and subfolders mixed.

**Architecture:** Migrate from embedded `List<CPYSnippet>` on `CPYFolder` to a parent-pointer model: both `CPYFolder` and `CPYSnippet` carry a `parentIdentifier` that points to the owning folder (empty = root). Children of a folder are derived by query: `(folders ∪ snippets where parent==X).sorted(by: index)`. Editor `NSOutlineView`, menubar popup builder, drag-and-drop, XML import/export, and the Realm migration block are all rewritten around this model. Schema bumps 8→9 (additive: add `parentIdentifier`, backfill from old `snippets` list) and 9→10 (drop the `snippets` list and the `folder` LinkingObjects). Each commit between bumps must compile and pass tests.

**Tech Stack:** Swift 6 (strict concurrency), Cocoa, RealmSwift, AEXML, Quick + Nimble, Magnet (hotkeys). Build: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`. Test: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test`. Project file edits in `Clipy.xcodeproj/project.pbxproj` use the existing AppIndexScanRootSpec pattern (`AB05xxxxxxxxxxxxxxxxXXXX` UUIDs) for new test files.

**Spec:** `docs/superpowers/specs/2026-05-10-nested-snippets-design.md` (read this first for design rationale).

**Pre-reads (project conventions):**
- `CLAUDE.md` (build rules, commit-message style, no AI attribution)
- `AGENTS.md` (Swift 6 / Sendable conventions, editor invariants)
- Spec file above

---

## File map

**Modified:**
- `Clipy/Sources/Models/CPYFolder.swift` — drop `snippets` List, add `parentIdentifier`, add tree helpers, drop snippet-list mutators.
- `Clipy/Sources/Models/CPYSnippet.swift` — drop `folders` LinkingObjects + `folder` accessor + `ignoredProperties`, add `parentIdentifier`.
- `Clipy/Sources/Models/CPYDraggedData.swift` — replace `folderIdentifier`/`snippetIdentifier` with `identifier` + `parentIdentifier`.
- `Clipy/Sources/Extensions/Realm+Migration.swift` — bump schema 8→9 (additive backfill) then 9→10 (drop properties).
- `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift` — Realm-backed access, IBActions for nested adds/deletes/depth checks, hotkey panel for any folder.
- `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift` — recursive data source, drop validation with cycle + depth, renumber helper, recursive XML import/export.
- `Clipy/Sources/Managers/MenuManager+MenuBuilders.swift` — recursive `appendChildren`.
- `Clipy/Sources/Constants.swift` — add `Constants.Xml.foldersElement`.
- `ClipyTests/FolderSpec.swift` — replace removed-API tests with parent-pointer / depth / children specs.
- `ClipyTests/SnippetSpec.swift` — add `parentIdentifier` round-trip.
- `ClipyTests/DraggedDataSpec.swift` — update for new `CPYDraggedData` shape.
- `ClipyTests/RealmMigrationSpec.swift` — bump expected schemaVersion to 10, add migration-helper unit tests.

**Created:**
- `ClipyTests/NestedDragDropSpec.swift` — cycle, depth, move tests.
- `ClipyTests/SnippetXmlRoundTripSpec.swift` — recursive XML import/export round-trip; backward compat.
- `Clipy.xcodeproj/project.pbxproj` — register the two new test files.

---

## Conventions for every task

- Build before commit: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build` (NEVER `clean build`).
- Test before commit: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test` (or run the specific spec class through Xcode test plan).
- Commit messages: short imperative English, no `feat:`/`fix:` prefix, no AI attribution. (See `CLAUDE.md`.)
- One logical change per commit.

---

### Task 1: Refactor `CPYDraggedData` to identifier + parentIdentifier

**Files:**
- Modify: `Clipy/Sources/Models/CPYDraggedData.swift`
- Modify: `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift`
- Modify: `ClipyTests/DraggedDataSpec.swift`

- [ ] **Step 1: Update the failing test (rewrite DraggedDataSpec)**

Replace the body of `ClipyTests/DraggedDataSpec.swift` with:

```swift
import Quick
import Nimble
import Foundation
@testable import Clipy

class DraggedDataSpec: QuickSpec {
    override class func spec() {

        describe("NSCoding") {

            it("Archive folder data") {
                let id = UUID().uuidString
                let parent = UUID().uuidString
                let draggedData = CPYDraggedData(type: .folder, identifier: id, parentIdentifier: parent, index: 10)
                let data = try NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: true)

                let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: CPYDraggedData.self, from: data)
                expect(unarchived).toNot(beNil())
                expect(unarchived?.type) == draggedData.type
                expect(unarchived?.identifier) == id
                expect(unarchived?.parentIdentifier) == parent
                expect(unarchived?.index) == 10
            }

            it("Archive snippet data with empty parent string is preserved") {
                // Snippets always have a non-empty parentIdentifier; we still
                // verify the empty-string round-trip for safety.
                let draggedData = CPYDraggedData(type: .snippet, identifier: "s", parentIdentifier: "", index: 0)
                let data = try NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: true)
                let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: CPYDraggedData.self, from: data)
                expect(unarchived?.parentIdentifier) == ""
                expect(unarchived?.identifier) == "s"
            }
        }
    }
}
```

- [ ] **Step 2: Run test to confirm it fails to compile**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: FAIL — `Cannot convert value of type 'String' to expected argument type` or similar (the new initializer signature does not exist yet).

- [ ] **Step 3: Replace `CPYDraggedData` with the new shape**

Overwrite `Clipy/Sources/Models/CPYDraggedData.swift` with:

```swift
//
//  CPYDraggedData.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/07/14.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

final class CPYDraggedData: NSObject, NSSecureCoding {

    // MARK: - Properties
    let type: DragType
    let identifier: String
    let parentIdentifier: String
    let index: Int

    // MARK: - Enums
    enum DragType: Int {
        case folder, snippet
    }

    // MARK: - Initialize
    init(type: DragType, identifier: String, parentIdentifier: String, index: Int) {
        self.type = type
        self.identifier = identifier
        self.parentIdentifier = parentIdentifier
        self.index = index
        super.init()
    }

    // MARK: - NSSecureCoding
    static var supportsSecureCoding: Bool { true }

    required init?(coder aDecoder: NSCoder) {
        self.type = DragType(rawValue: aDecoder.decodeInteger(forKey: "type")) ?? .folder
        self.identifier = (aDecoder.decodeObject(of: NSString.self, forKey: "identifier") as String?) ?? ""
        self.parentIdentifier = (aDecoder.decodeObject(of: NSString.self, forKey: "parentIdentifier") as String?) ?? ""
        self.index = aDecoder.decodeInteger(forKey: "index")
        super.init()
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(type.rawValue, forKey: "type")
        aCoder.encode(identifier as NSString, forKey: "identifier")
        aCoder.encode(parentIdentifier as NSString, forKey: "parentIdentifier")
        aCoder.encode(index, forKey: "index")
    }
}
```

- [ ] **Step 4: Update the only caller in OutlineDataSource to use new fields**

In `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift`, update `pasteboardWriterForItem` to construct the new shape (existing accept/validate code references `draggedData.folderIdentifier` / `draggedData.snippetIdentifier`; update them to `draggedData.identifier` and look up the parent via `draggedData.parentIdentifier`). Replace the `pasteboardWriterForItem` body with:

```swift
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        if let folder = item as? CPYFolder, let index = folders.firstIndex(of: folder) {
            let draggedData = CPYDraggedData(type: .folder, identifier: folder.identifier, parentIdentifier: "", index: index)
            guard let data = LegacyKeyedArchive.archivedData(withRootObject: draggedData) else { return nil }
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else if let snippet = item as? CPYSnippet, let folder = outlineView.parent(forItem: snippet) as? CPYFolder {
            guard let index = folder.snippets.firstIndex(of: snippet) else { return nil }
            let draggedData = CPYDraggedData(type: .snippet, identifier: snippet.identifier, parentIdentifier: folder.identifier, index: Int(index))
            guard let data = LegacyKeyedArchive.archivedData(withRootObject: draggedData) else { return nil }
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else {
            return nil
        }
        return pasteboardItem
    }
```

Then in `validateDrop` and `acceptDrop`, replace every reference to `draggedData.folderIdentifier` with `draggedData.identifier` and every reference to `draggedData.snippetIdentifier` with `draggedData.identifier`. The existing `where: { $0.identifier == draggedData.folderIdentifier }` becomes `where: { $0.identifier == draggedData.identifier }`. Update both .folder and .snippet cases.

- [ ] **Step 5: Build and run tests**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/DraggedDataSpec`
Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Clipy/Sources/Models/CPYDraggedData.swift \
        Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift \
        ClipyTests/DraggedDataSpec.swift
git commit -m "rename CPYDraggedData fields to identifier and parentIdentifier"
```

---

### Task 2: Add `parentIdentifier` to models, schema bump 8→9 with backfill

This is the additive schema change. The old `snippets` List on `CPYFolder` and `folders` LinkingObjects on `CPYSnippet` stay in place; existing code keeps compiling and using them. The migration block backfills `parentIdentifier` from the existing `snippets` list.

**Files:**
- Modify: `Clipy/Sources/Models/CPYFolder.swift`
- Modify: `Clipy/Sources/Models/CPYSnippet.swift`
- Modify: `Clipy/Sources/Extensions/Realm+Migration.swift`
- Modify: `ClipyTests/RealmMigrationSpec.swift`

- [ ] **Step 1: Add a failing test for the bumped schema version**

In `ClipyTests/RealmMigrationSpec.swift`, change the line that asserts schemaVersion to:

```swift
            it("installs schemaVersion 9 onto the default configuration") {
                Realm.migration()
                expect(Realm.Configuration.defaultConfiguration.schemaVersion) == 9
            }
```

(Replace the existing `it("installs schemaVersion 8 ...")` block.)

- [ ] **Step 2: Add a unit test for the backfill helper (does not yet exist)**

Append a new `describe` block inside `RealmMigrationSpec.spec()`:

```swift
        describe("Snippet parentIdentifier backfill") {
            it("maps snippets to their containing folder identifier") {
                let folderA = "folder-A"
                let folderB = "folder-B"
                let snippetsByFolder: [String: [String]] = [
                    folderA: ["s1", "s2"],
                    folderB: ["s3"]
                ]
                let map = SnippetParentBackfill.parentMap(folders: snippetsByFolder)
                expect(map.count) == 3
                expect(map["s1"]) == folderA
                expect(map["s2"]) == folderA
                expect(map["s3"]) == folderB
            }

            it("orphan snippets (not in any folder) get an empty parent") {
                let map = SnippetParentBackfill.parentMap(folders: ["fA": ["s1"]])
                expect(SnippetParentBackfill.parentFor(snippetId: "missing", in: map)) == ""
                expect(SnippetParentBackfill.parentFor(snippetId: "s1", in: map)) == "fA"
            }
        }
```

- [ ] **Step 3: Build to confirm tests fail to compile**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: FAIL — `Cannot find 'SnippetParentBackfill' in scope` and `expect(...) == 9` fails (schema is still 8).

- [ ] **Step 4: Add `parentIdentifier` to `CPYFolder`**

In `Clipy/Sources/Models/CPYFolder.swift`, add the property right after `identifier`:

```swift
    @objc dynamic var index = 0
    @objc dynamic var enable = true
    @objc dynamic var title = ""
    @objc dynamic var identifier = UUID().uuidString
    @objc dynamic var parentIdentifier = ""
    let snippets = List<CPYSnippet>()
```

- [ ] **Step 5: Add `parentIdentifier` to `CPYSnippet`**

In `Clipy/Sources/Models/CPYSnippet.swift`, add the property right after `identifier`:

```swift
    @objc dynamic var index = 0
    @objc dynamic var enable = true
    @objc dynamic var title = ""
    @objc dynamic var content = ""
    @objc dynamic var identifier = UUID().uuidString
    @objc dynamic var parentIdentifier = ""
    let folders = LinkingObjects(fromType: CPYFolder.self, property: "snippets")
```

- [ ] **Step 6: Bump schema to 9 and add migration block**

Replace the body of `Realm.migration()` in `Clipy/Sources/Extensions/Realm+Migration.swift` with:

```swift
extension Realm {
    static func migration() {
        // Schema 9 introduces parentIdentifier on CPYFolder and CPYSnippet
        // (preparation for nested snippet folders). Folders default to root
        // ("" parentIdentifier). Snippets are backfilled to point at the
        // folder that currently contains them via the legacy `snippets` list.
        var config = Realm.Configuration(schemaVersion: 9, migrationBlock: { migration, oldSchemaVersion in
            if oldSchemaVersion <= 2 {
                migration.enumerateObjects(ofType: CPYSnippet.className()) { _, newObject in
                    guard let newObject = newObject else { return }
                    newObject["identifier"] = UUID().uuidString
                }
            }
            if oldSchemaVersion <= 4 {
                migration.enumerateObjects(ofType: CPYFolder.className()) { _, newObject in
                    guard let newObject = newObject else { return }
                    newObject["identifier"] = UUID().uuidString
                }
            }
            if oldSchemaVersion <= 5 {
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
```

The `import Foundation` and `import RealmSwift` lines at the top of the file are unchanged.

- [ ] **Step 7: Build and run tests**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/RealmMigrationSpec`
Expected: 6 tests pass (the original 5 + 2 new backfill tests, with the renamed schema-version assertion).

- [ ] **Step 8: Commit**

```bash
git add Clipy/Sources/Models/CPYFolder.swift \
        Clipy/Sources/Models/CPYSnippet.swift \
        Clipy/Sources/Extensions/Realm+Migration.swift \
        ClipyTests/RealmMigrationSpec.swift
git commit -m "add parentIdentifier to folder/snippet and backfill on schema v9"
```

---

### Task 3: Add tree helpers to `CPYFolder` (children, depth, renumber, addChildFolder, removeRecursive)

Pure additions. The old `snippets` List remains — these helpers live alongside it. Helpers are small, pure-Realm, and test-friendly.

**Files:**
- Modify: `Clipy/Sources/Models/CPYFolder.swift`
- Modify: `ClipyTests/FolderSpec.swift` (append a new `describe` block; do not touch existing blocks yet)

- [ ] **Step 1: Write failing tests for the tree helpers**

Append the following `describe` block at the end of `FolderSpec.spec()` (right before the final closing brace of the class):

```swift
        describe("Tree helpers (parentIdentifier model)") {

            it("children(of:) merges folders and snippets sorted by index") {
                let realm = try! Realm()
                let parent = CPYFolder()
                parent.title = "P"; parent.index = 0
                realm.transaction { realm.add(parent) }

                let snippet = CPYSnippet()
                snippet.title = "snippet"; snippet.index = 1
                snippet.parentIdentifier = parent.identifier

                let subfolder = CPYFolder()
                subfolder.title = "sub"; subfolder.index = 0
                subfolder.parentIdentifier = parent.identifier

                let snippet2 = CPYSnippet()
                snippet2.title = "snippet2"; snippet2.index = 2
                snippet2.parentIdentifier = parent.identifier

                realm.transaction {
                    realm.add(snippet); realm.add(subfolder); realm.add(snippet2)
                }

                let kids = CPYFolder.children(parentIdentifier: parent.identifier, in: realm)
                expect(kids.count) == 3
                expect((kids[0] as? CPYFolder)?.title) == "sub"      // index 0
                expect((kids[1] as? CPYSnippet)?.title) == "snippet"  // index 1
                expect((kids[2] as? CPYSnippet)?.title) == "snippet2" // index 2
            }

            it("depth(of:) returns 1 for a root folder, N for an N-deep folder") {
                let realm = try! Realm()
                var prevID = ""
                var folders: [CPYFolder] = []
                for i in 0..<5 {
                    let f = CPYFolder(); f.title = "L\(i + 1)"; f.index = 0
                    f.parentIdentifier = prevID
                    realm.transaction { realm.add(f) }
                    folders.append(f)
                    prevID = f.identifier
                }
                expect(CPYFolder.depth(of: folders[0], in: realm)) == 1
                expect(CPYFolder.depth(of: folders[1], in: realm)) == 2
                expect(CPYFolder.depth(of: folders[4], in: realm)) == 5
            }

            it("maxDescendantDepth(of:) returns 1 for a leaf folder, N for an N-level subtree") {
                let realm = try! Realm()
                let root = CPYFolder(); root.title = "R"; root.index = 0
                realm.transaction { realm.add(root) }
                expect(CPYFolder.maxDescendantDepth(of: root, in: realm)) == 1

                let a = CPYFolder(); a.title = "A"; a.index = 0; a.parentIdentifier = root.identifier
                realm.transaction { realm.add(a) }
                expect(CPYFolder.maxDescendantDepth(of: root, in: realm)) == 2

                let b = CPYFolder(); b.title = "B"; b.index = 0; b.parentIdentifier = a.identifier
                realm.transaction { realm.add(b) }
                expect(CPYFolder.maxDescendantDepth(of: root, in: realm)) == 3
                expect(CPYFolder.maxDescendantDepth(of: a, in: realm)) == 2
            }

            it("isDescendant(_:of:) detects ancestry up to root") {
                let realm = try! Realm()
                let r = CPYFolder(); r.index = 0
                realm.transaction { realm.add(r) }
                let a = CPYFolder(); a.index = 0; a.parentIdentifier = r.identifier
                realm.transaction { realm.add(a) }
                let b = CPYFolder(); b.index = 0; b.parentIdentifier = a.identifier
                realm.transaction { realm.add(b) }

                expect(CPYFolder.isDescendant(b, of: r, in: realm)) == true
                expect(CPYFolder.isDescendant(b, of: a, in: realm)) == true
                expect(CPYFolder.isDescendant(a, of: b, in: realm)) == false
                expect(CPYFolder.isDescendant(r, of: r, in: realm)) == false
            }

            it("renumberSiblings(of:) assigns 0..n-1 in current index order across mixed children") {
                let realm = try! Realm()
                let p = CPYFolder(); p.index = 0
                realm.transaction { realm.add(p) }

                let f1 = CPYFolder(); f1.parentIdentifier = p.identifier; f1.index = 100
                let s1 = CPYSnippet(); s1.parentIdentifier = p.identifier; s1.index = 50
                let f2 = CPYFolder(); f2.parentIdentifier = p.identifier; f2.index = 200
                realm.transaction { realm.add(f1); realm.add(s1); realm.add(f2) }

                CPYFolder.renumberSiblings(of: p.identifier, in: realm)

                expect(s1.index) == 0
                expect(f1.index) == 1
                expect(f2.index) == 2
            }
        }
```

- [ ] **Step 2: Build to confirm the tests fail to compile**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: FAIL — `Type 'CPYFolder' has no member 'children'` (and similar for `depth`, `maxDescendantDepth`, `isDescendant`, `renumberSiblings`).

- [ ] **Step 3: Implement the tree helpers in `CPYFolder.swift`**

Append to `Clipy/Sources/Models/CPYFolder.swift` (after the existing `Migrate Index` extension):

```swift
// MARK: - Tree (parentIdentifier model)
extension CPYFolder {

    /// Returns the merged, index-sorted children (`[CPYFolder | CPYSnippet]`)
    /// of the folder identified by `parentIdentifier`. Pass `""` for roots.
    static func children(parentIdentifier: String, in realm: Realm) -> [Object] {
        let folders = realm.objects(CPYFolder.self).filter("parentIdentifier == %@", parentIdentifier)
        let snippets = realm.objects(CPYSnippet.self).filter("parentIdentifier == %@", parentIdentifier)
        var merged: [Object] = []
        merged.append(contentsOf: folders)
        merged.append(contentsOf: snippets)
        merged.sort { lhs, rhs in
            let li = (lhs as? CPYFolder)?.index ?? (lhs as? CPYSnippet)?.index ?? 0
            let ri = (rhs as? CPYFolder)?.index ?? (rhs as? CPYSnippet)?.index ?? 0
            return li < ri
        }
        return merged
    }

    /// Depth of `folder`: 1 for a root folder, N for an N-deep folder.
    static func depth(of folder: CPYFolder, in realm: Realm) -> Int {
        var d = 1
        var pid = folder.parentIdentifier
        while !pid.isEmpty {
            guard let p = realm.object(ofType: CPYFolder.self, forPrimaryKey: pid) else { break }
            d += 1
            pid = p.parentIdentifier
            if d > 1024 { break } // guard against pathological data
        }
        return d
    }

    /// Number of folder levels in the subtree rooted at `folder` (1 = leaf folder
    /// with no subfolders, 2 = folder with one level of subfolders, …).
    static func maxDescendantDepth(of folder: CPYFolder, in realm: Realm) -> Int {
        let subfolders = realm.objects(CPYFolder.self).filter("parentIdentifier == %@", folder.identifier)
        if subfolders.isEmpty { return 1 }
        return 1 + (subfolders.map { maxDescendantDepth(of: $0, in: realm) }.max() ?? 0)
    }

    /// True if `candidate` is the same as or a descendant of `ancestor`. Used for cycle prevention
    /// before reparenting a folder. Returns false for `candidate == ancestor` (callers normally
    /// reject self-drops separately) — actually the cycle check needs to consider self too: we walk
    /// the chain UP from `candidate` and see if we ever hit `ancestor`. Convention: `isDescendant(c, of: a)`
    /// returns true iff `a` is reachable by walking parentIdentifier from `c`.
    static func isDescendant(_ candidate: CPYFolder, of ancestor: CPYFolder, in realm: Realm) -> Bool {
        var pid = candidate.parentIdentifier
        while !pid.isEmpty {
            if pid == ancestor.identifier { return true }
            guard let p = realm.object(ofType: CPYFolder.self, forPrimaryKey: pid) else { return false }
            pid = p.parentIdentifier
        }
        return false
    }

    /// Renumber the children of a parent (by parent identifier) so their `index`
    /// fields are 0..n-1 in current sort order. Must be called inside a Realm
    /// transaction OR will start its own transaction. We choose: caller is
    /// responsible for the transaction (so callers can batch).
    static func renumberSiblings(of parentIdentifier: String, in realm: Realm) {
        let kids = children(parentIdentifier: parentIdentifier, in: realm)
        let writeBlock = {
            for (i, kid) in kids.enumerated() {
                if let f = kid as? CPYFolder { f.index = i }
                else if let s = kid as? CPYSnippet { s.index = i }
            }
        }
        if realm.isInWriteTransaction {
            writeBlock()
        } else {
            try? realm.write { writeBlock() }
        }
    }
}
```

- [ ] **Step 4: Build and run tests**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/FolderSpec`
Expected: all FolderSpec tests pass (the 5 new "Tree helpers" tests plus the existing legacy tests, which still work because the `snippets` List remains).

- [ ] **Step 5: Commit**

```bash
git add Clipy/Sources/Models/CPYFolder.swift ClipyTests/FolderSpec.swift
git commit -m "add tree helpers to CPYFolder (children/depth/renumber/isDescendant)"
```

---

### Task 4: Rewrite menubar popup builder to use parent-pointer tree

> **Heads-up:** between this commit and Task 5, snippets created through the editor's legacy `createSnippet`/`mergeSnippet` paths now also need their `parentIdentifier` populated, otherwise newly-added snippets are invisible to the new menu builder (which filters by `parentIdentifier`). This task covers that patch in Step 0 below.

**Files:**
- Modify: `Clipy/Sources/Models/CPYFolder.swift` (legacy add paths set `parentIdentifier`)
- Modify: `Clipy/Sources/Managers/MenuManager+MenuBuilders.swift`

- [ ] **Step 0: Patch the legacy snippet-add paths to populate `parentIdentifier`**

In `Clipy/Sources/Models/CPYFolder.swift`, update `createSnippet()` to set the parent identifier on the new snippet:

```swift
    func createSnippet() -> CPYSnippet {
        let snippet = CPYSnippet()
        snippet.title = "untitled snippet"
        snippet.index = Int(snippets.count)
        snippet.parentIdentifier = identifier
        return snippet
    }
```

And update `mergeSnippet` to stamp `parentIdentifier` on the copy before insertion:

```swift
    func mergeSnippet(_ snippet: CPYSnippet) {
        guard let realm = Realm.safeInstance() else { return }
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: identifier) else { return }
        let copySnippet = CPYSnippet(value: snippet)
        copySnippet.parentIdentifier = folder.identifier
        folder.realm?.transaction { folder.snippets.append(copySnippet) }
    }
```

(The `insertSnippet` path takes an already-saved snippet whose `parentIdentifier` was set by either of the above; nothing to change there.)

- [ ] **Step 1: Replace `addSnippetItems` with the recursive version**

In `Clipy/Sources/Managers/MenuManager+MenuBuilders.swift`, replace the entire `// MARK: - Snippets` extension (currently `addSnippetItems` and `makeSnippetMenuItem`) with:

```swift
// MARK: - Snippets
extension MenuManager {
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool, settings: MenuSettings) {
        guard let realm = realm else { return }
        let roots = realm.objects(CPYFolder.self)
            .filter("parentIdentifier == ''")
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
            .filter { $0.enable }
        guard !roots.isEmpty else { return }

        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        let labelItem = NSMenuItem(title: L10n.snippet, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        for root in roots {
            let subMenuItem = makeSubmenuItem(root.title, isShowIcon: settings.isShowIcon)
            menu.addItem(subMenuItem)
            if let submenu = subMenuItem.submenu {
                appendSnippetChildren(submenu, parentId: root.identifier, realm: realm, settings: settings)
            }
        }
    }

    private func appendSnippetChildren(_ menu: NSMenu, parentId: String, realm: Realm, settings: MenuSettings) {
        let firstIndex = settings.isStartFromZero ? 0 : 1
        var listNumber = firstIndex
        let kids = CPYFolder.children(parentIdentifier: parentId, in: realm)
        for kid in kids {
            if let folder = kid as? CPYFolder {
                guard folder.enable else { continue }
                let subMenuItem = makeSubmenuItem(folder.title, isShowIcon: settings.isShowIcon)
                menu.addItem(subMenuItem)
                if let submenu = subMenuItem.submenu {
                    appendSnippetChildren(submenu, parentId: folder.identifier, realm: realm, settings: settings)
                }
            } else if let snippet = kid as? CPYSnippet {
                guard snippet.enable else { continue }
                menu.addItem(makeSnippetMenuItem(snippet, listNumber: listNumber, settings: settings))
                listNumber += 1
            }
        }
    }

    func makeSnippetMenuItem(_ snippet: CPYSnippet, listNumber: Int, settings: MenuSettings? = nil) -> NSMenuItem {
        let isMarkWithNumber = settings?.isMarkWithNumber ?? AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = settings?.isShowIcon ?? AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)

        let title = trimTitle(snippet.title, maxLength: settings?.maxMenuItemTitleLength)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippet.identifier
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil

        return menuItem
    }
}
```

The change: roots are now folders with `parentIdentifier == ""` (instead of all folders sorted by index — which used to mean all folders since all were "root"). `appendSnippetChildren` handles every level uniformly.

- [ ] **Step 2: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

- [ ] **Step 3: Manual smoke (optional but recommended)**

After Task 2 + 4, existing user data (still flat) should render identically in the menubar:
1. Build Release into the local dir per `CLAUDE.md`:
   ```
   xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
     CONFIGURATION_BUILD_DIR=/Users/ank/dev/clipy/build/Release build
   ```
2. Quit the running Clipy and `open /Users/ank/dev/clipy/build/Release/Clipy.app`.
3. Click the menubar item — snippet folders + their snippets should appear identically to before.

(If something is missing, the most likely cause is that `parentIdentifier` was not backfilled — which means migration was skipped because the user's realm was already at the new schema before the backfill code ran. In that case manually run a one-off cleanup or re-test on a fresh realm.)

- [ ] **Step 4: Commit**

```bash
git add Clipy/Sources/Models/CPYFolder.swift \
        Clipy/Sources/Managers/MenuManager+MenuBuilders.swift
git commit -m "rewrite snippet menu builder to walk parentIdentifier tree"
```

---

### Task 5: Rewrite editor data source and IBActions to use the parent-pointer tree

The editor currently holds `var folders = [CPYFolder]()` of detached deep copies. We replace that with Realm-backed access (live `Results` + helper). Mutations go through Realm transactions.

**Files:**
- Modify: `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift`
- Modify: `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift`

- [ ] **Step 1: Replace the controller's data cache and selection helpers**

In `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift`, replace this block (lines around 49–62):

```swift
    var folders = [CPYFolder]()
    private var selectedSnippet: CPYSnippet? {
        guard let snippet = outlineView.item(atRow: outlineView.selectedRow) as? CPYSnippet else { return nil }
        return snippet
    }
    private var selectedFolder: CPYFolder? {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
        if let folder = outlineView.parent(forItem: item) as? CPYFolder {
            return folder
        } else if let folder = item as? CPYFolder {
            return folder
        }
        return nil
    }
```

with:

```swift
    /// Cache of `(parentIdentifier → children)` for the outline view's data source
    /// methods. Invalidated by `reloadOutline()` before every reload.
    private var childrenCache: [String: [Object]] = [:]

    func children(parentId: String) -> [Object] {
        if let cached = childrenCache[parentId] { return cached }
        guard let realm = Realm.safeInstance() else { return [] }
        let kids = CPYFolder.children(parentIdentifier: parentId, in: realm)
        childrenCache[parentId] = kids
        return kids
    }

    func reloadOutline() {
        childrenCache.removeAll()
        outlineView.reloadData()
    }

    private var selectedSnippet: CPYSnippet? {
        guard let snippet = outlineView.item(atRow: outlineView.selectedRow) as? CPYSnippet else { return nil }
        return snippet
    }

    /// The folder that should "host" a new snippet/subfolder for the current selection.
    /// If a folder is selected → that folder. If a snippet is selected → its parent folder
    /// (looked up by parentIdentifier). If nothing is selected → nil.
    private var selectedHostFolder: CPYFolder? {
        guard let realm = Realm.safeInstance() else { return nil }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
        if let folder = item as? CPYFolder { return folder }
        if let snippet = item as? CPYSnippet, !snippet.parentIdentifier.isEmpty {
            return realm.object(ofType: CPYFolder.self, forPrimaryKey: snippet.parentIdentifier)
        }
        return nil
    }
```

- [ ] **Step 2: Replace `windowDidLoad` body to drop the deepCopy bootstrap**

Find this in `windowDidLoad`:

```swift
        guard let realm = Realm.safeInstance() else { return }
        folders = realm.objects(CPYFolder.self)
                    .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
                    .map { $0.deepCopy() }
        outlineView.reloadData()
        // Select first folder
        if let folder = folders.first {
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
            changeItemFocus()
        }
```

Replace with:

```swift
        reloadOutline()
        // Select first root folder
        if let realm = Realm.safeInstance(),
           let firstRoot = realm.objects(CPYFolder.self)
               .filter("parentIdentifier == ''")
               .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
               .first {
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: firstRoot)), byExtendingSelection: false)
            changeItemFocus()
        }
```

- [ ] **Step 3: Rewrite `addSnippetButtonTapped`**

Replace it with:

```swift
    @IBAction private func addSnippetButtonTapped(_ sender: AnyObject) {
        guard let realm = Realm.safeInstance() else { NSSound.beep(); return }
        guard let host = selectedHostFolder else { NSSound.beep(); return }
        let snippet = CPYSnippet()
        snippet.title = "untitled snippet"
        snippet.parentIdentifier = host.identifier
        snippet.index = children(parentId: host.identifier).count
        try? realm.write { realm.add(snippet) }
        reloadOutline()
        outlineView.expandItem(host)
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: snippet)), byExtendingSelection: false)
        changeItemFocus()
    }
```

- [ ] **Step 4: Rewrite `addFolderButtonTapped` (depth-aware)**

Replace it with:

```swift
    @IBAction private func addFolderButtonTapped(_ sender: AnyObject) {
        guard let realm = Realm.safeInstance() else { NSSound.beep(); return }
        let host: CPYFolder? = selectedHostFolder
        // If host exists, new folder becomes its child — but only if depth(host) < 5.
        if let host = host, CPYFolder.depth(of: host, in: realm) >= 5 {
            NSSound.beep(); return
        }
        let folder = CPYFolder()
        folder.title = "untitled folder"
        folder.parentIdentifier = host?.identifier ?? ""
        folder.index = children(parentId: folder.parentIdentifier).count
        try? realm.write { realm.add(folder) }
        reloadOutline()
        if let host = host { outlineView.expandItem(host) }
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
        changeItemFocus()
    }
```

- [ ] **Step 5: Rewrite `deleteButtonTapped` (cascade)**

Replace it with:

```swift
    @IBAction private func deleteButtonTapped(_ sender: AnyObject) {
        guard let realm = Realm.safeInstance() else { NSSound.beep(); return }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            NSSound.beep(); return
        }

        let alert = NSAlert()
        alert.messageText = L10n.deleteItem
        alert.informativeText = L10n.areYouSureWantToDeleteThisItem
        alert.addButton(withTitle: L10n.deleteItem)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

        try? realm.write {
            if let folder = item as? CPYFolder {
                deleteFolderRecursively(folder, in: realm)
            } else if let snippet = item as? CPYSnippet {
                let parentId = snippet.parentIdentifier
                realm.delete(snippet)
                CPYFolder.renumberSiblings(of: parentId, in: realm)
            }
        }
        reloadOutline()
        changeItemFocus()
    }

    private func deleteFolderRecursively(_ folder: CPYFolder, in realm: Realm) {
        // Collect descendant folder identifiers so we can unregister hotkeys.
        var idsToUnregister: [String] = [folder.identifier]
        var stack: [CPYFolder] = [folder]
        while let f = stack.popLast() {
            let subs = realm.objects(CPYFolder.self).filter("parentIdentifier == %@", f.identifier)
            for s in subs {
                idsToUnregister.append(s.identifier)
                stack.append(s)
            }
        }
        // Delete descendants bottom-up: snippets, then folders.
        for fid in idsToUnregister {
            let snippets = realm.objects(CPYSnippet.self).filter("parentIdentifier == %@", fid)
            realm.delete(snippets)
        }
        for fid in idsToUnregister.reversed() {
            if let f = realm.object(ofType: CPYFolder.self, forPrimaryKey: fid) {
                realm.delete(f)
            }
        }
        // Unregister hotkeys for every removed folder.
        for fid in idsToUnregister {
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: fid)
        }
        // Renumber the parent's remaining siblings.
        CPYFolder.renumberSiblings(of: folder.parentIdentifier, in: realm)
    }
```

- [ ] **Step 6: Rewrite `changeStatusButtonTapped` (in-place toggle)**

Replace it with:

```swift
    @IBAction private func changeStatusButtonTapped(_ sender: AnyObject) {
        guard let realm = Realm.safeInstance() else { NSSound.beep(); return }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            NSSound.beep(); return
        }
        try? realm.write {
            if let folder = item as? CPYFolder {
                folder.enable.toggle()
            } else if let snippet = item as? CPYSnippet {
                snippet.enable.toggle()
            }
        }
        reloadOutline()
        changeItemFocus()
    }
```

- [ ] **Step 7: Update XML import**

Replace the body of `importSnippetButtonTapped` with the recursive version:

```swift
    @IBAction private func importSnippetButtonTapped(_ sender: AnyObject) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.allowedContentTypes = [.xml]
        let returnCode = panel.runModal()
        if returnCode != NSApplication.ModalResponse.OK { return }

        guard let url = panel.urls.first, let data = try? Data(contentsOf: url) else { return }

        do {
            guard let realm = Realm.safeInstance() else { return }
            let lastRoot = realm.objects(CPYFolder.self)
                .filter("parentIdentifier == ''")
                .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true).last
            var rootIndex = (lastRoot?.index ?? -1) + 1
            var options = AEXMLOptions()
            options.parserSettings.shouldTrimWhitespace = false
            let xmlDocument = try AEXMLDocument(xml: data, options: options)
            try realm.write {
                xmlDocument[Constants.Xml.rootElement][Constants.Xml.folderElement].all?.forEach { folderElement in
                    importFolder(folderElement, parentId: "", index: rootIndex, in: realm)
                    rootIndex += 1
                }
            }
            reloadOutline()
        } catch {
            NSSound.beep()
        }
    }

    private func importFolder(_ element: AEXMLElement, parentId: String, index: Int, in realm: Realm) {
        let folder = CPYFolder()
        folder.title = element[Constants.Xml.titleElement].value ?? "untitled folder"
        folder.parentIdentifier = parentId
        folder.index = index
        realm.add(folder)
        var snippetIndex = 0
        element[Constants.Xml.snippetsElement][Constants.Xml.snippetElement].all?.forEach { sEl in
            let s = CPYSnippet()
            s.title = sEl[Constants.Xml.titleElement].value ?? "untitled snippet"
            s.content = sEl[Constants.Xml.contentElement].value ?? ""
            s.parentIdentifier = folder.identifier
            s.index = snippetIndex
            realm.add(s)
            snippetIndex += 1
        }
        var childIndex = 0
        element[Constants.Xml.foldersElement][Constants.Xml.folderElement].all?.forEach { childEl in
            importFolder(childEl, parentId: folder.identifier, index: childIndex, in: realm)
            childIndex += 1
        }
    }
```

(The `Constants.Xml.foldersElement` constant is added in Task 7. This task assumes Task 7 already added it — order matters! See Task 7 ordering note below.)

**Order fix:** swap Step 7 of this task to come AFTER Task 7's Step 1, OR add the constant inline now. To keep tasks self-contained, **insert the constant now**: open `Clipy/Sources/Constants.swift` and inside the `struct Xml { ... }` add:

```swift
        static let foldersElement = "folders"
```

(Task 7 will then just consume this constant.)

- [ ] **Step 8: Update XML export**

Replace the body of `exportSnippetButtonTapped` with:

```swift
    @IBAction private func exportSnippetButtonTapped(_ sender: AnyObject) {
        let xmlDocument = AEXMLDocument()
        let rootElement = xmlDocument.addChild(name: Constants.Xml.rootElement)

        guard let realm = Realm.safeInstance() else { return }
        let roots = realm.objects(CPYFolder.self)
            .filter("parentIdentifier == ''")
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        for folder in roots {
            exportFolder(folder, into: rootElement, realm: realm)
        }

        let panel = NSSavePanel()
        panel.accessoryView = nil
        panel.canSelectHiddenExtension = true
        panel.allowedContentTypes = [.xml]
        panel.allowsOtherFileTypes = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.nameFieldStringValue = "snippets"
        let returnCode = panel.runModal()
        if returnCode != NSApplication.ModalResponse.OK { return }

        guard let xmlData = xmlDocument.xml.data(using: String.Encoding.utf8) else { return }
        guard let url = panel.url else { return }

        do { try xmlData.write(to: url, options: .atomic) } catch { NSSound.beep() }
    }

    private func exportFolder(_ folder: CPYFolder, into parent: AEXMLElement, realm: Realm) {
        let folderElement = parent.addChild(name: Constants.Xml.folderElement)
        folderElement.addChild(name: Constants.Xml.titleElement, value: folder.title)

        let snippetsElement = folderElement.addChild(name: Constants.Xml.snippetsElement)
        let snippets = realm.objects(CPYSnippet.self)
            .filter("parentIdentifier == %@", folder.identifier)
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
        for s in snippets {
            let sEl = snippetsElement.addChild(name: Constants.Xml.snippetElement)
            sEl.addChild(name: Constants.Xml.titleElement, value: s.title)
            sEl.addChild(name: Constants.Xml.contentElement, value: s.content)
        }

        let subfolders = realm.objects(CPYFolder.self)
            .filter("parentIdentifier == %@", folder.identifier)
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        if !subfolders.isEmpty {
            let foldersElement = folderElement.addChild(name: Constants.Xml.foldersElement)
            for sub in subfolders {
                exportFolder(sub, into: foldersElement, realm: realm)
            }
        }
    }
```

- [ ] **Step 9: Update `changeItemFocus` to allow hotkey panel for any selected folder**

In `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift`, the existing `changeItemFocus` already shows `folderSettingView` for any selected `CPYFolder` (regardless of depth). No change needed; just verify after the rewrite that this method still compiles unmodified.

- [ ] **Step 10: Update RecordView delegate to allow hotkey on any folder**

The existing methods `recordViewShouldBeginRecording`, `recordView(_:canRecordKeyCombo:)`, and `recordView(_:didChangeKeyCombo:)` use `selectedFolder`. Update them to use `selectedHostFolder` instead — but `selectedHostFolder` returns nil for snippet-only contexts which is what we want. Search/replace `selectedFolder` → `selectedHostFolder` in the `RecordViewDelegate` extension.

- [ ] **Step 11: Update `control(_:textShouldEndEditing:)` for inline rename**

In the `NSOutlineViewDelegate` extension, the existing `control(_:textShouldEndEditing:)` calls `folder.merge()` and `snippet.merge()`. With Realm-backed data, the live object is already in Realm, so these calls become `try? realm.write { folder.title = text }` (and similarly for snippet). Replace the body with:

```swift
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        let text = fieldEditor.string
        guard !text.isEmpty else { return false }
        guard let outlineView = control as? NSOutlineView else { return false }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return false }
        guard let realm = Realm.safeInstance() else { return false }
        try? realm.write {
            if let folder = item as? CPYFolder { folder.title = text }
            else if let snippet = item as? CPYSnippet { snippet.title = text }
        }
        changeItemFocus()
        return true
    }
```

- [ ] **Step 12: Update `textView(_:shouldChangeTextIn:replacementString:)` similarly**

Replace its body with:

```swift
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString = replacementString else { return false }
        let text = textView.string
        guard let snippet = selectedSnippet else { return false }
        guard let realm = Realm.safeInstance() else { return false }
        guard let range = Range(affectedCharRange, in: text) else { return false }
        var string = text
        string.replaceSubrange(range, with: replacementString)
        try? realm.write { snippet.content = string }
        return true
    }
```

- [ ] **Step 13: Rewrite the `NSOutlineViewDataSource` methods for the parent-pointer tree**

Replace the data-source extension at the top of `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift` (the four methods `numberOfChildrenOfItem`, `isItemExpandable`, `child:ofItem`, `objectValueFor:byItem`) with:

```swift
extension CPYSnippetsEditorWindowController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return children(parentId: "").count }
        if let folder = item as? CPYFolder { return children(parentId: folder.identifier).count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let folder = item as? CPYFolder { return !children(parentId: folder.identifier).isEmpty }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let parentId = (item as? CPYFolder)?.identifier ?? ""
        let kids = children(parentId: parentId)
        if index < 0 || index >= kids.count { return "" }
        return kids[index]
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        if let folder = item as? CPYFolder { return folder.title }
        if let snippet = item as? CPYSnippet { return snippet.title }
        return ""
    }

    // MARK: - Drag and Drop (rewritten in Task 6 below)
```

(Leave the existing drag-drop methods in place for now; Task 6 rewrites them. The `pasteboardWriterForItem` from Task 1 still references `folders.firstIndex(of: folder)`, which we removed in this task — this will cause a build break here. Replace its body with the parent-aware version now to keep the build green:)

Replace `pasteboardWriterForItem` with:

```swift
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        if let folder = item as? CPYFolder {
            let parentId = folder.parentIdentifier
            let index = children(parentId: parentId).firstIndex(where: { ($0 as? CPYFolder)?.identifier == folder.identifier }) ?? 0
            let dragged = CPYDraggedData(type: .folder, identifier: folder.identifier, parentIdentifier: parentId, index: index)
            guard let data = LegacyKeyedArchive.archivedData(withRootObject: dragged) else { return nil }
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else if let snippet = item as? CPYSnippet {
            let parentId = snippet.parentIdentifier
            let index = children(parentId: parentId).firstIndex(where: { ($0 as? CPYSnippet)?.identifier == snippet.identifier }) ?? 0
            let dragged = CPYDraggedData(type: .snippet, identifier: snippet.identifier, parentIdentifier: parentId, index: index)
            guard let data = LegacyKeyedArchive.archivedData(withRootObject: dragged) else { return nil }
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else {
            return nil
        }
        return pasteboardItem
    }
```

Leave `validateDrop` and `acceptDrop` as they are (Task 6 rewrites them). They will continue to compile because they only reference `draggedData.identifier` (after Task 1) and use the `folders` array via `folders.first(where:)` — but `folders` was removed! Replace those lookups now to keep the build green:

In `acceptDrop`, change `folders.first(where: { $0.identifier == draggedData.identifier })` to `realm.object(ofType: CPYFolder.self, forPrimaryKey: draggedData.identifier)` — and `folders.insert(folder, at: index)` / `folders.remove(at:)` calls become writes via realm. Since Task 6 rewrites this entirely, just replace the whole `acceptDrop` body with a temporary stub that returns `false` (no drag-drop until Task 6 fills it in):

```swift
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        // Rewritten in the next commit (Task 6 of nested-snippets plan).
        return false
    }
```

And likewise `validateDrop` may stay as-is from Task 1 (uses `draggedData.type`), or also stub:

```swift
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        return NSDragOperation()
    }
```

This deliberately disables drag-and-drop for one commit. The next task (Task 6) restores it with depth and cycle checks.

- [ ] **Step 14: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

- [ ] **Step 15: Manual smoke (recommended)**

1. Build Release.
2. Open the snippets editor (`AppDelegate.showSnippetEditorWindow`) — verify the existing folders/snippets render correctly, you can add a folder/snippet, rename inline, toggle enable, delete with cascade. Drag-drop should not work in this commit.

- [ ] **Step 16: Commit**

```bash
git add Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift \
        Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift \
        Clipy/Sources/Constants.swift
git commit -m "rewrite snippets editor data source and IBActions for nested model"
```

---

### Task 6: Rewrite drag-and-drop with cycle and depth checks; add `NestedDragDropSpec`

**Files:**
- Modify: `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift` (replace stubs from Task 5)
- Create: `ClipyTests/NestedDragDropSpec.swift`
- Modify: `Clipy.xcodeproj/project.pbxproj` (register the new test file)

- [ ] **Step 1: Write the failing tests**

Create `ClipyTests/NestedDragDropSpec.swift` with:

```swift
import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class NestedDragDropSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        afterEach {
            let realm = try! Realm()
            try? realm.write { realm.deleteAll() }
        }

        describe("DropValidator (folder)") {

            it("rejects moving a folder onto itself") {
                let realm = try! Realm()
                let f = CPYFolder(); f.index = 0
                try! realm.write { realm.add(f) }
                let r = DropValidator.validateFolderMove(movedId: f.identifier, targetParentId: f.identifier, in: realm)
                expect(r) == false
            }

            it("rejects moving a folder under one of its descendants (cycle)") {
                let realm = try! Realm()
                let a = CPYFolder(); a.index = 0
                try! realm.write { realm.add(a) }
                let b = CPYFolder(); b.parentIdentifier = a.identifier; b.index = 0
                try! realm.write { realm.add(b) }
                let r = DropValidator.validateFolderMove(movedId: a.identifier, targetParentId: b.identifier, in: realm)
                expect(r) == false
            }

            it("rejects moves that would push depth above 5") {
                let realm = try! Realm()
                // Build a 4-deep chain: r1 -> r2 -> r3 -> r4
                var prev = ""
                var ids: [String] = []
                for _ in 0..<4 {
                    let f = CPYFolder(); f.parentIdentifier = prev; f.index = 0
                    try! realm.write { realm.add(f) }
                    prev = f.identifier
                    ids.append(f.identifier)
                }
                // A 2-level subtree: x -> y
                let x = CPYFolder(); x.index = 0
                try! realm.write { realm.add(x) }
                let y = CPYFolder(); y.parentIdentifier = x.identifier; y.index = 0
                try! realm.write { realm.add(y) }

                // Moving x (height 2) under r4 (depth 4) → final deepest depth = 4 + 2 = 6, reject.
                let r = DropValidator.validateFolderMove(movedId: x.identifier, targetParentId: ids[3], in: realm)
                expect(r) == false

                // Moving x (height 2) under r3 (depth 3) → final deepest depth = 3 + 2 = 5, allow.
                let r2 = DropValidator.validateFolderMove(movedId: x.identifier, targetParentId: ids[2], in: realm)
                expect(r2) == true
            }

            it("allows valid folder moves") {
                let realm = try! Realm()
                let a = CPYFolder(); a.index = 0
                try! realm.write { realm.add(a) }
                let b = CPYFolder(); b.index = 1
                try! realm.write { realm.add(b) }
                let r = DropValidator.validateFolderMove(movedId: a.identifier, targetParentId: b.identifier, in: realm)
                expect(r) == true
            }
        }

        describe("DropValidator (snippet)") {

            it("rejects snippet moves to root") {
                let r = DropValidator.validateSnippetMove(targetParentId: "", in: try! Realm())
                expect(r) == false
            }

            it("allows snippet moves to any folder regardless of depth") {
                let realm = try! Realm()
                var prev = ""
                var ids: [String] = []
                for _ in 0..<5 {
                    let f = CPYFolder(); f.parentIdentifier = prev; f.index = 0
                    try! realm.write { realm.add(f) }
                    prev = f.identifier
                    ids.append(f.identifier)
                }
                expect(DropValidator.validateSnippetMove(targetParentId: ids[4], in: realm)) == true
            }
        }

        describe("Move execution") {

            it("moves a snippet across folders and renumbers both old and new parents") {
                let realm = try! Realm()
                let p1 = CPYFolder(); p1.index = 0
                let p2 = CPYFolder(); p2.index = 1
                try! realm.write { realm.add(p1); realm.add(p2) }

                let s1 = CPYSnippet(); s1.parentIdentifier = p1.identifier; s1.index = 0
                let s2 = CPYSnippet(); s2.parentIdentifier = p1.identifier; s2.index = 1
                try! realm.write { realm.add(s1); realm.add(s2) }

                try! realm.write {
                    NestedMoveExecutor.move(itemId: s1.identifier, isFolder: false,
                                            toParentId: p2.identifier, atIndex: 0, in: realm)
                }
                expect(s1.parentIdentifier) == p2.identifier
                expect(s1.index) == 0
                expect(s2.index) == 0
            }

            it("moves a folder and updates its parent without breaking the subtree") {
                let realm = try! Realm()
                let r1 = CPYFolder(); r1.index = 0
                let r2 = CPYFolder(); r2.index = 1
                try! realm.write { realm.add(r1); realm.add(r2) }

                let mid = CPYFolder(); mid.parentIdentifier = r1.identifier; mid.index = 0
                let leaf = CPYSnippet(); leaf.parentIdentifier = ""  // set after mid exists
                try! realm.write { realm.add(mid) }
                leaf.parentIdentifier = mid.identifier; leaf.index = 0
                try! realm.write { realm.add(leaf) }

                try! realm.write {
                    NestedMoveExecutor.move(itemId: mid.identifier, isFolder: true,
                                            toParentId: r2.identifier, atIndex: 0, in: realm)
                }
                expect(mid.parentIdentifier) == r2.identifier
                expect(leaf.parentIdentifier) == mid.identifier // unchanged
                expect(leaf.index) == 0
            }
        }
    }
}
```

- [ ] **Step 2: Register the new test file in `Clipy.xcodeproj/project.pbxproj`**

Open `Clipy.xcodeproj/project.pbxproj`. Use the same UUID style as `AppIndexScanRootSpec.swift` (which is the most recently added test file). Pick fresh UUIDs `AB05000000000000000B0001` (file ref) and `AB05000000000000000B0002` (build ref). Make four insertions:

(a) In the **PBXBuildFile** section (near other `*Spec.swift in Sources` lines, e.g. near `AB05000000000000000A0002`):

```
		AB05000000000000000B0002 /* NestedDragDropSpec.swift in Sources */ = {isa = PBXBuildFile; fileRef = AB05000000000000000B0001 /* NestedDragDropSpec.swift */; };
```

(b) In the **PBXFileReference** section (near `AB05000000000000000A0001`):

```
		AB05000000000000000B0001 /* NestedDragDropSpec.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = NestedDragDropSpec.swift; sourceTree = "<group>"; };
```

(c) In the **PBXGroup** that lists `ClipyTests` children (the same group containing `AB05000000000000000A0001 /* AppIndexScanRootSpec.swift */`), add:

```
				AB05000000000000000B0001 /* NestedDragDropSpec.swift */,
```

(d) In the **PBXSourcesBuildPhase** for the test target (the same one containing `AB05000000000000000A0002 /* AppIndexScanRootSpec.swift in Sources */`), add:

```
				AB05000000000000000B0002 /* NestedDragDropSpec.swift in Sources */,
```

- [ ] **Step 3: Build to confirm tests fail to compile (helpers don't exist)**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: FAIL — `Cannot find 'DropValidator' in scope`, `Cannot find 'NestedMoveExecutor' in scope`.

- [ ] **Step 4: Implement `DropValidator` and `NestedMoveExecutor`**

Append to `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift` (above the trailing `}` of the file, at file scope — these are top-level helper enums):

```swift
// MARK: - Drag & Drop helpers (testable)

enum DropValidator {
    /// Returns true iff a folder with `movedId` may be reparented under `targetParentId`.
    /// Rules: no self-drop, no cycle, depth(target) + height(moved) ≤ 5.
    static func validateFolderMove(movedId: String, targetParentId: String, in realm: Realm) -> Bool {
        if movedId == targetParentId { return false }
        guard let moved = realm.object(ofType: CPYFolder.self, forPrimaryKey: movedId) else { return false }
        let targetDepth: Int
        if targetParentId.isEmpty {
            targetDepth = 0
        } else {
            guard let target = realm.object(ofType: CPYFolder.self, forPrimaryKey: targetParentId) else { return false }
            // Cycle: target must not be the moved folder or any of its descendants.
            if target.identifier == moved.identifier { return false }
            if CPYFolder.isDescendant(target, of: moved, in: realm) { return false }
            targetDepth = CPYFolder.depth(of: target, in: realm)
        }
        let height = CPYFolder.maxDescendantDepth(of: moved, in: realm)
        return (targetDepth + height) <= 5
    }

    /// Returns true iff a snippet may be placed under `targetParentId`.
    /// Rules: target must be a folder (non-empty parent id) — no depth limit.
    static func validateSnippetMove(targetParentId: String, in realm: Realm) -> Bool {
        if targetParentId.isEmpty { return false }
        return realm.object(ofType: CPYFolder.self, forPrimaryKey: targetParentId) != nil
    }
}

enum NestedMoveExecutor {
    /// Reparents an item (folder or snippet) under `toParentId` at position `atIndex`
    /// (a value of -1 means append at end). Renumbers the old and new parents'
    /// children so siblings stay 0..n-1. Caller must hold an open Realm write
    /// transaction.
    static func move(itemId: String, isFolder: Bool, toParentId: String, atIndex: Int, in realm: Realm) {
        let oldParentId: String
        if isFolder {
            guard let f = realm.object(ofType: CPYFolder.self, forPrimaryKey: itemId) else { return }
            oldParentId = f.parentIdentifier
            f.parentIdentifier = toParentId
        } else {
            guard let s = realm.object(ofType: CPYSnippet.self, forPrimaryKey: itemId) else { return }
            oldParentId = s.parentIdentifier
            s.parentIdentifier = toParentId
        }
        // Compute new ordering for new parent: collect children, position `itemId` at `atIndex`.
        let kids = CPYFolder.children(parentIdentifier: toParentId, in: realm)
        // The moved item is already in `kids` (we set parentIdentifier above), so locate and reposition it.
        var ordered: [Object] = []
        for kid in kids where idOf(kid) != itemId { ordered.append(kid) }
        let target = realm.object(ofType: isFolder ? CPYFolder.self : CPYSnippet.self, forPrimaryKey: itemId)
        if let target = target {
            let pos = (atIndex < 0 || atIndex > ordered.count) ? ordered.count : atIndex
            ordered.insert(target, at: pos)
        }
        for (i, kid) in ordered.enumerated() {
            if let f = kid as? CPYFolder { f.index = i }
            else if let s = kid as? CPYSnippet { s.index = i }
        }
        // Renumber old parent if different.
        if oldParentId != toParentId {
            CPYFolder.renumberSiblings(of: oldParentId, in: realm)
        }
    }

    private static func idOf(_ obj: Object) -> String {
        if let f = obj as? CPYFolder { return f.identifier }
        if let s = obj as? CPYSnippet { return s.identifier }
        return ""
    }
}
```

Note: the `realm.object(ofType: isFolder ? CPYFolder.self : CPYSnippet.self, ...)` line uses a conditional expression for type. Swift cannot infer `Object.Type` like that directly with `forPrimaryKey`. Replace with an explicit branch:

```swift
        let target: Object?
        if isFolder {
            target = realm.object(ofType: CPYFolder.self, forPrimaryKey: itemId)
        } else {
            target = realm.object(ofType: CPYSnippet.self, forPrimaryKey: itemId)
        }
```

(Use this form when writing the file.)

- [ ] **Step 5: Replace the validateDrop and acceptDrop stubs with real logic**

In `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift`, replace the stub `validateDrop` and `acceptDrop` (added in Task 5) with:

```swift
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard let realm = Realm.safeInstance() else { return NSDragOperation() }
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return NSDragOperation() }
        guard let dragged = LegacyKeyedArchive.unarchivedObject(of: CPYDraggedData.self, from: data) else { return NSDragOperation() }
        let targetParentId = (item as? CPYFolder)?.identifier ?? ""

        switch dragged.type {
        case .folder:
            return DropValidator.validateFolderMove(movedId: dragged.identifier, targetParentId: targetParentId, in: realm) ? .move : NSDragOperation()
        case .snippet:
            return DropValidator.validateSnippetMove(targetParentId: targetParentId, in: realm) ? .move : NSDragOperation()
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let realm = Realm.safeInstance() else { return false }
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return false }
        guard let dragged = LegacyKeyedArchive.unarchivedObject(of: CPYDraggedData.self, from: data) else { return false }
        let targetParentId = (item as? CPYFolder)?.identifier ?? ""

        // Final-mile validation (the source pasteboard is trusted, but state may have changed).
        switch dragged.type {
        case .folder:
            guard DropValidator.validateFolderMove(movedId: dragged.identifier, targetParentId: targetParentId, in: realm) else { return false }
        case .snippet:
            guard DropValidator.validateSnippetMove(targetParentId: targetParentId, in: realm) else { return false }
        }

        // No-op if target == source position.
        if dragged.parentIdentifier == targetParentId && dragged.index == index { return false }

        try? realm.write {
            NestedMoveExecutor.move(itemId: dragged.identifier,
                                    isFolder: dragged.type == .folder,
                                    toParentId: targetParentId,
                                    atIndex: index,
                                    in: realm)
        }
        reloadOutline()
        if let parent = item as? CPYFolder { outlineView.expandItem(parent) }
        let movedItem: Any?
        if dragged.type == .folder {
            movedItem = realm.object(ofType: CPYFolder.self, forPrimaryKey: dragged.identifier)
        } else {
            movedItem = realm.object(ofType: CPYSnippet.self, forPrimaryKey: dragged.identifier)
        }
        if let movedItem = movedItem {
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: movedItem)), byExtendingSelection: false)
            changeItemFocus()
        }
        return true
    }
```

- [ ] **Step 6: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

- [ ] **Step 7: Run tests**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/NestedDragDropSpec`
Expected: all 7 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift \
        ClipyTests/NestedDragDropSpec.swift \
        Clipy.xcodeproj/project.pbxproj
git commit -m "add nested drag and drop with cycle and depth checks"
```

---

### Task 7: Add `SnippetXmlRoundTripSpec` for recursive XML import/export

The XML import and export were already rewritten in Task 5 (Steps 7–8). This task only adds the test that proves the recursive logic works and that old flat XML still imports correctly.

**Files:**
- Create: `ClipyTests/SnippetXmlRoundTripSpec.swift`
- Modify: `Clipy.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing test**

Create `ClipyTests/SnippetXmlRoundTripSpec.swift` with:

```swift
import Quick
import Nimble
import Foundation
import RealmSwift
import AEXML
@testable import Clipy

class SnippetXmlRoundTripSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        afterEach {
            let realm = try! Realm()
            try? realm.write { realm.deleteAll() }
        }

        describe("Old flat XML import (backward compat)") {
            it("imports a single-level folder with snippets and no nested folders element") {
                let xml = """
                <folders>
                  <folder>
                    <title>Greetings</title>
                    <snippets>
                      <snippet><title>hello</title><content>Hello, world!</content></snippet>
                    </snippets>
                  </folder>
                </folders>
                """
                let realm = try! Realm()
                try! realm.write { realm.deleteAll() }
                let imported = try SnippetXml.importDocument(data: xml.data(using: .utf8)!, into: realm, startingRootIndex: 0)
                expect(imported) == 1
                let folders = realm.objects(CPYFolder.self).filter("parentIdentifier == ''")
                expect(folders.count) == 1
                expect(folders.first?.title) == "Greetings"
                let snippets = realm.objects(CPYSnippet.self)
                expect(snippets.count) == 1
                expect(snippets.first?.parentIdentifier) == folders.first?.identifier
                expect(snippets.first?.title) == "hello"
                expect(snippets.first?.content) == "Hello, world!"
            }
        }

        describe("Round-trip with nesting") {
            it("export then import reproduces the same 3-level tree") {
                let realm = try! Realm()
                try! realm.write { realm.deleteAll() }

                // Build: Root1 → SubA (with snippet "x"), SubB → Leaf (with snippet "y")
                let r1 = CPYFolder(); r1.title = "Root1"; r1.index = 0
                try! realm.write { realm.add(r1) }
                let a = CPYFolder(); a.title = "SubA"; a.parentIdentifier = r1.identifier; a.index = 0
                try! realm.write { realm.add(a) }
                let sx = CPYSnippet(); sx.title = "x"; sx.content = "X"; sx.parentIdentifier = a.identifier; sx.index = 0
                try! realm.write { realm.add(sx) }
                let b = CPYFolder(); b.title = "SubB"; b.parentIdentifier = r1.identifier; b.index = 1
                try! realm.write { realm.add(b) }
                let leaf = CPYFolder(); leaf.title = "Leaf"; leaf.parentIdentifier = b.identifier; leaf.index = 0
                try! realm.write { realm.add(leaf) }
                let sy = CPYSnippet(); sy.title = "y"; sy.content = "Y"; sy.parentIdentifier = leaf.identifier; sy.index = 0
                try! realm.write { realm.add(sy) }

                let xmlData = try SnippetXml.exportDocument(from: realm).xml.data(using: .utf8)!

                // Wipe and re-import.
                try! realm.write { realm.deleteAll() }
                _ = try SnippetXml.importDocument(data: xmlData, into: realm, startingRootIndex: 0)

                let roots = realm.objects(CPYFolder.self).filter("parentIdentifier == ''")
                expect(roots.count) == 1
                let root = roots.first!
                expect(root.title) == "Root1"
                let kids = CPYFolder.children(parentIdentifier: root.identifier, in: realm)
                expect(kids.count) == 2
                expect((kids[0] as? CPYFolder)?.title) == "SubA"
                expect((kids[1] as? CPYFolder)?.title) == "SubB"

                let aId = (kids[0] as! CPYFolder).identifier
                let aKids = CPYFolder.children(parentIdentifier: aId, in: realm)
                expect(aKids.count) == 1
                expect((aKids[0] as? CPYSnippet)?.title) == "x"
                expect((aKids[0] as? CPYSnippet)?.content) == "X"

                let bId = (kids[1] as! CPYFolder).identifier
                let bKids = CPYFolder.children(parentIdentifier: bId, in: realm)
                expect(bKids.count) == 1
                expect((bKids[0] as? CPYFolder)?.title) == "Leaf"

                let leafId = (bKids[0] as! CPYFolder).identifier
                let leafKids = CPYFolder.children(parentIdentifier: leafId, in: realm)
                expect(leafKids.count) == 1
                expect((leafKids[0] as? CPYSnippet)?.title) == "y"
                expect((leafKids[0] as? CPYSnippet)?.content) == "Y"
            }
        }
    }
}
```

- [ ] **Step 2: Build to confirm tests fail to compile**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: FAIL — `Cannot find 'SnippetXml' in scope`.

- [ ] **Step 3: Extract the import/export logic from the editor into a testable type**

The recursive XML import/export was inlined into `CPYSnippetsEditorWindowController` in Task 5. Extract them now into a new top-level enum `SnippetXml` so the spec can call them without instantiating the editor window.

In `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift` (or a new file `Clipy/Sources/Snippets/SnippetXml.swift` if you prefer — both work; the plan keeps it in the existing file to avoid a third pbxproj edit), add at file scope:

```swift
import AEXML

// MARK: - Snippet XML import/export (testable)

enum SnippetXml {
    /// Returns the number of root folders imported.
    @discardableResult
    static func importDocument(data: Data, into realm: Realm, startingRootIndex: Int) throws -> Int {
        var options = AEXMLOptions()
        options.parserSettings.shouldTrimWhitespace = false
        let xml = try AEXMLDocument(xml: data, options: options)
        var rootIndex = startingRootIndex
        var imported = 0
        try realm.write {
            xml[Constants.Xml.rootElement][Constants.Xml.folderElement].all?.forEach { folderElement in
                importFolder(folderElement, parentId: "", index: rootIndex, in: realm)
                rootIndex += 1
                imported += 1
            }
        }
        return imported
    }

    static func exportDocument(from realm: Realm) -> AEXMLDocument {
        let doc = AEXMLDocument()
        let root = doc.addChild(name: Constants.Xml.rootElement)
        let roots = realm.objects(CPYFolder.self)
            .filter("parentIdentifier == ''")
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        for folder in roots {
            exportFolder(folder, into: root, realm: realm)
        }
        return doc
    }

    private static func importFolder(_ element: AEXMLElement, parentId: String, index: Int, in realm: Realm) {
        let folder = CPYFolder()
        folder.title = element[Constants.Xml.titleElement].value ?? "untitled folder"
        folder.parentIdentifier = parentId
        folder.index = index
        realm.add(folder)
        var snippetIndex = 0
        element[Constants.Xml.snippetsElement][Constants.Xml.snippetElement].all?.forEach { sEl in
            let s = CPYSnippet()
            s.title = sEl[Constants.Xml.titleElement].value ?? "untitled snippet"
            s.content = sEl[Constants.Xml.contentElement].value ?? ""
            s.parentIdentifier = folder.identifier
            s.index = snippetIndex
            realm.add(s)
            snippetIndex += 1
        }
        var childIndex = 0
        element[Constants.Xml.foldersElement][Constants.Xml.folderElement].all?.forEach { childEl in
            importFolder(childEl, parentId: folder.identifier, index: childIndex, in: realm)
            childIndex += 1
        }
    }

    private static func exportFolder(_ folder: CPYFolder, into parent: AEXMLElement, realm: Realm) {
        let folderElement = parent.addChild(name: Constants.Xml.folderElement)
        folderElement.addChild(name: Constants.Xml.titleElement, value: folder.title)

        let snippetsElement = folderElement.addChild(name: Constants.Xml.snippetsElement)
        let snippets = realm.objects(CPYSnippet.self)
            .filter("parentIdentifier == %@", folder.identifier)
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
        for s in snippets {
            let sEl = snippetsElement.addChild(name: Constants.Xml.snippetElement)
            sEl.addChild(name: Constants.Xml.titleElement, value: s.title)
            sEl.addChild(name: Constants.Xml.contentElement, value: s.content)
        }

        let subfolders = realm.objects(CPYFolder.self)
            .filter("parentIdentifier == %@", folder.identifier)
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        if !subfolders.isEmpty {
            let foldersElement = folderElement.addChild(name: Constants.Xml.foldersElement)
            for sub in subfolders {
                exportFolder(sub, into: foldersElement, realm: realm)
            }
        }
    }
}
```

(The `import AEXML` line at the top of the file may already be present; do not duplicate.)

- [ ] **Step 4: Switch the editor's IBActions to call `SnippetXml`**

In `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift`, replace the body of `importSnippetButtonTapped` (added in Task 5) with:

```swift
    @IBAction private func importSnippetButtonTapped(_ sender: AnyObject) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.allowedContentTypes = [.xml]
        let returnCode = panel.runModal()
        if returnCode != NSApplication.ModalResponse.OK { return }
        guard let url = panel.urls.first, let data = try? Data(contentsOf: url) else { return }

        do {
            guard let realm = Realm.safeInstance() else { return }
            let lastRoot = realm.objects(CPYFolder.self)
                .filter("parentIdentifier == ''")
                .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true).last
            let startIndex = (lastRoot?.index ?? -1) + 1
            _ = try SnippetXml.importDocument(data: data, into: realm, startingRootIndex: startIndex)
            reloadOutline()
        } catch {
            NSSound.beep()
        }
    }
```

And replace the body of `exportSnippetButtonTapped` with:

```swift
    @IBAction private func exportSnippetButtonTapped(_ sender: AnyObject) {
        guard let realm = Realm.safeInstance() else { return }
        let xmlDocument = SnippetXml.exportDocument(from: realm)

        let panel = NSSavePanel()
        panel.accessoryView = nil
        panel.canSelectHiddenExtension = true
        panel.allowedContentTypes = [.xml]
        panel.allowsOtherFileTypes = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.nameFieldStringValue = "snippets"
        let returnCode = panel.runModal()
        if returnCode != NSApplication.ModalResponse.OK { return }

        guard let xmlData = xmlDocument.xml.data(using: .utf8), let url = panel.url else { return }
        do { try xmlData.write(to: url, options: .atomic) } catch { NSSound.beep() }
    }
```

Delete the now-unused `private func importFolder(...)` and `private func exportFolder(...)` from the editor (those were added in Task 5 Step 7/8 and are replaced by `SnippetXml`).

- [ ] **Step 5: Register the new spec in `Clipy.xcodeproj/project.pbxproj`**

Use UUIDs `AB05000000000000000C0001` (file ref) and `AB05000000000000000C0002` (build ref). Insert four lines analogously to Task 6 Step 2:

```
		AB05000000000000000C0002 /* SnippetXmlRoundTripSpec.swift in Sources */ = {isa = PBXBuildFile; fileRef = AB05000000000000000C0001 /* SnippetXmlRoundTripSpec.swift */; };
		AB05000000000000000C0001 /* SnippetXmlRoundTripSpec.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = SnippetXmlRoundTripSpec.swift; sourceTree = "<group>"; };
				AB05000000000000000C0001 /* SnippetXmlRoundTripSpec.swift */,
				AB05000000000000000C0002 /* SnippetXmlRoundTripSpec.swift in Sources */,
```

(In their respective sections — see Task 6 Step 2 for the four-section pattern.)

- [ ] **Step 6: Build and run tests**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/SnippetXmlRoundTripSpec`
Expected: 2 tests pass.

- [ ] **Step 7: Commit**

```bash
git add ClipyTests/SnippetXmlRoundTripSpec.swift \
        Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift \
        Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift \
        Clipy.xcodeproj/project.pbxproj
git commit -m "extract SnippetXml import/export and add round-trip spec"
```

---

### Task 8: Drop legacy `snippets` List and `folders` LinkingObjects, schema bump 9→10

Now that no production code uses `CPYFolder.snippets` or `CPYSnippet.folders`, drop them and bump the schema. Also clean up the deprecated mutator methods on `CPYFolder` and update the existing `FolderSpec` tests that exercise them.

**Files:**
- Modify: `Clipy/Sources/Models/CPYFolder.swift`
- Modify: `Clipy/Sources/Models/CPYSnippet.swift`
- Modify: `Clipy/Sources/Extensions/Realm+Migration.swift`
- Modify: `ClipyTests/RealmMigrationSpec.swift`
- Modify: `ClipyTests/FolderSpec.swift` (remove or rewrite tests that depend on dropped APIs)
- Modify: `ClipyTests/SnippetSpec.swift` (small additions)

- [ ] **Step 1: Verify nothing in the production code references the dropped APIs**

Run: `grep -rn 'snippets.append\|snippets.firstIndex\|snippets.insert\|snippets.remove\|\.folder\b\|LinkingObjects' Clipy/Sources/ | grep -v '\.git'`
Expected: only matches inside `Clipy/Sources/Models/CPYSnippet.swift` (the `folders` LinkingObjects definition and `folder` accessor) and `Clipy/Sources/Models/CPYFolder.swift` (the `snippets` List and the `mergeSnippet/insertSnippet/removeSnippet/rearrangesSnippetIndex/createSnippet/deepCopy` methods). If any other file shows up, fix it before continuing.

- [ ] **Step 2: Update `FolderSpec` to drop tests that depend on the legacy API**

In `ClipyTests/FolderSpec.swift`, remove these blocks entirely:
- `it("deep copy object") { ... }` — relies on `folder.snippets.append`.
- `it("Create snippet") { ... }` — relies on `folder.createSnippet()` and `folder.snippets.append`.
- `it("Merge snippet") { ... }` — uses `copyFolder.mergeSnippet`.
- `it("Insert snippet") { ... }` — uses `copyFolder.insertSnippet`.
- `it("Remove snippet") { ... }` — uses `copyFolder.removeSnippet`.
- `it("Remove folder") { ... }` — uses `folder.snippets.append` to seed; rewrite to seed via `parentIdentifier`:

  Replace the body with:
  ```swift
              it("Remove folder cascades to snippet children") {
                  let realm = try! Realm()
                  let folder = CPYFolder(); folder.title = "F"; folder.index = 0
                  try! realm.write { realm.add(folder) }
                  let snippet = CPYSnippet(); snippet.parentIdentifier = folder.identifier; snippet.index = 0
                  try! realm.write { realm.add(snippet) }

                  expect(realm.objects(CPYFolder.self).count) == 1
                  expect(realm.objects(CPYSnippet.self).count) == 1

                  // The new flow is: caller deletes the folder along with its
                  // descendants. We assert this contract by hand here (the
                  // editor's deleteFolderRecursively does the same).
                  try! realm.write {
                      let snippets = realm.objects(CPYSnippet.self).filter("parentIdentifier == %@", folder.identifier)
                      realm.delete(snippets)
                      realm.delete(folder)
                  }

                  expect(realm.objects(CPYFolder.self).count) == 0
                  expect(realm.objects(CPYSnippet.self).count) == 0
              }
  ```
- `it("Rearrange snippet index") { ... }` — uses `folder.snippets.append` and `copyFolder.rearrangesSnippetIndex()`. Drop entirely; the new equivalent (`renumberSiblings`) is already covered in Task 3's "Tree helpers" describe block.

Keep:
- `it("Create folder") { ... }` (uses only `CPYFolder.create()` which is still valid).
- `it("Merge folder") { ... }` (uses only `folder.merge()` which still works).
- `it("Rearrange folder index") { ... }` (uses only `CPYFolder.rearrangesIndex` which still works).
- The entire "Tree helpers" describe block from Task 3.

- [ ] **Step 3: Drop `CPYFolder.snippets` List and the snippet-list mutators**

In `Clipy/Sources/Models/CPYFolder.swift`:

(a) Remove the `let snippets = List<CPYSnippet>()` line (line ~23 originally).

(b) Remove the entire `// MARK: - Add Snippet` extension (functions `createSnippet`, `mergeSnippet`, `insertSnippet`, `removeSnippet`).

(c) Remove `rearrangesSnippetIndex()` from the `// MARK: - Migrate Index` extension (the static `rearrangesIndex` for folders stays).

(d) In the `// MARK: - Copy` extension, simplify `deepCopy()` since there is no longer a snippets list to copy:

```swift
// MARK: - Copy
extension CPYFolder {
    func deepCopy() -> CPYFolder {
        return CPYFolder(value: self)
    }
}
```

(e) In the `// MARK: - Remove Folder` extension, replace the body to drop the `delete(folder.snippets)` line (which referenced the now-removed property):

```swift
// MARK: - Remove Folder
extension CPYFolder {
    func remove() {
        guard let realm = Realm.safeInstance() else { return }
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: identifier) else { return }
        folder.realm?.transaction {
            // Note: snippet/subfolder cascade is the editor's responsibility now
            // (see deleteFolderRecursively in CPYSnippetsEditorWindowController).
            folder.realm?.delete(folder)
        }
    }
}
```

- [ ] **Step 4: Drop `CPYSnippet.folders` LinkingObjects and `folder` accessor**

In `Clipy/Sources/Models/CPYSnippet.swift`:

(a) Remove the `let folders = LinkingObjects(fromType: CPYFolder.self, property: "snippets")` line.

(b) Remove the `var folder: CPYFolder?` computed property entirely.

(c) Remove the entire `override static func ignoredProperties() -> [String] { return ["folder"] }` method.

The final file should be:

```swift
//
//  CPYSnippet.swift
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

final class CPYSnippet: Object {

    // MARK: - Properties
    @objc dynamic var index = 0
    @objc dynamic var enable = true
    @objc dynamic var title = ""
    @objc dynamic var content = ""
    @objc dynamic var identifier = UUID().uuidString
    @objc dynamic var parentIdentifier = ""

    // MARK: Primary Key
    override static func primaryKey() -> String? {
        return "identifier"
    }
}

// MARK: - Add Snippet
extension CPYSnippet {
    func merge() {
        guard let realm = Realm.safeInstance() else { return }
        let copySnippet = CPYSnippet(value: self)
        realm.transaction { realm.add(copySnippet, update: .all) }
    }
}

// MARK: - Remove Snippet
extension CPYSnippet {
    func remove() {
        guard let realm = Realm.safeInstance() else { return }
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: identifier) else { return }
        snippet.realm?.transaction { snippet.realm?.delete(snippet) }
    }
}
```

- [ ] **Step 5: Bump schema to 10**

In `Clipy/Sources/Extensions/Realm+Migration.swift`, change `schemaVersion: 9` to `schemaVersion: 10`. The migration block needs no changes for `oldSchemaVersion <= 9` because dropping properties is automatic (Realm detects the schema delta).

Update the leading comment to reflect the new bump:

```swift
        // Schema 10 drops CPYFolder.snippets (replaced by parentIdentifier on
        // CPYSnippet, populated in v9). Schema 9 introduced parentIdentifier
        // on CPYFolder and CPYSnippet for nested snippet folders. Folders
        // default to root (""). Snippets backfilled to point at the folder
        // that contained them via the legacy `snippets` list.
        var config = Realm.Configuration(schemaVersion: 10, migrationBlock: { migration, oldSchemaVersion in
```

- [ ] **Step 6: Update `RealmMigrationSpec` to expect schema 10**

In `ClipyTests/RealmMigrationSpec.swift`, change the `it("installs schemaVersion 9 ...")` test from Task 2 Step 1 to:

```swift
            it("installs schemaVersion 10 onto the default configuration") {
                Realm.migration()
                expect(Realm.Configuration.defaultConfiguration.schemaVersion) == 10
            }
```

The "supports the current schema" smoke test still applies — verify it does not depend on the dropped `snippets` list. The current text at line 73–94 only writes single objects, so no change is needed.

- [ ] **Step 7: Add `parentIdentifier` round-trip test to `SnippetSpec`**

In `ClipyTests/SnippetSpec.swift`, append inside the `describe("Sync database")` block:

```swift
            it("parentIdentifier round-trips through Realm") {
                let realm = try! Realm()
                let snippet = CPYSnippet(); snippet.parentIdentifier = "folder-1"
                try! realm.write { realm.add(snippet) }
                let fetched = realm.object(ofType: CPYSnippet.self, forPrimaryKey: snippet.identifier)
                expect(fetched?.parentIdentifier) == "folder-1"
            }
```

- [ ] **Step 8: Build and run all tests**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test`
Expected: all tests pass — `FolderSpec` (reduced), `SnippetSpec` (new round-trip), `RealmMigrationSpec` (schema 10), `DraggedDataSpec`, `NestedDragDropSpec`, `SnippetXmlRoundTripSpec`, plus pre-existing specs.

- [ ] **Step 9: Manual smoke (full feature)**

1. Build Release per `CLAUDE.md`.
2. Quit Clipy, open the new build.
3. In the snippets editor:
   - Add a root folder, add a subfolder, add a snippet inside the subfolder. Repeat to depth 5.
   - Try to add a 6th-level folder — should beep.
   - Drag a snippet between folders at different depths. Drag a folder under a sibling to nest it. Try to drag a folder into its own descendant — should be rejected.
   - Toggle enable on a folder; menubar popup should hide its subtree.
   - Set a hotkey on a deeply-nested folder; trigger the hotkey; popup should appear with that folder's children.
   - Export to XML, wipe folders manually (or import into a fresh Clipy install), import back — structure should match.
4. The menubar popup should reflect the tree as nested submenus matching the editor.

- [ ] **Step 10: Commit**

```bash
git add Clipy/Sources/Models/CPYFolder.swift \
        Clipy/Sources/Models/CPYSnippet.swift \
        Clipy/Sources/Extensions/Realm+Migration.swift \
        ClipyTests/RealmMigrationSpec.swift \
        ClipyTests/FolderSpec.swift \
        ClipyTests/SnippetSpec.swift
git commit -m "drop legacy snippet list and folder linking objects on schema v10"
```

---

## Final verification

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test`
Expected: all tests pass.

- [ ] **Step 2: Build Release and smoke-test once more**

Per `CLAUDE.md`:
```bash
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  CONFIGURATION_BUILD_DIR=/Users/ank/dev/clipy/build/Release build
```
Quit running Clipy and `open /Users/ank/dev/clipy/build/Release/Clipy.app`. Walk through the smoke checklist from Task 8 Step 9.

- [ ] **Step 3: Confirm git log is clean**

Run: `git log --oneline -10`
Expected: 8 commits, each in plain imperative English, no AI attribution.

---

## Notes

- **Schema two-step (v8→v9, v9→v10)** is intentional: it lets every commit between them compile and ship. A user who upgrades through both versions in one launch goes through both migrations in order — Realm handles this natively.
- **`children(of:)` perf**: per-reload caching in the editor avoids quadratic Realm hits while the outline view repeatedly asks for `numberOfChildrenOfItem` and `child:ofItem`. Menu builder does not cache (menus are built once per popup).
- **Outline expansion state** is reset by `reloadOutline()`. Future polish: persist expanded folder identifiers in `UserDefaults`. Out of scope for this plan.
- **Drag-and-drop disabled in Task 5**: between Task 5 and Task 6 commits the editor temporarily cannot drag-and-drop. If you stop work between those two commits, drag-drop will be broken. Always finish through Task 6 in one sitting.
