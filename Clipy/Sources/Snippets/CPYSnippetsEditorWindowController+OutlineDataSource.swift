//
//  CPYSnippetsEditorWindowController+OutlineDataSource.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RealmSwift

// MARK: - NSOutlineView DataSource
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

    // MARK: - Drag and Drop
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
                                    visibleIDs: visibleIdentifiersForMove(),
                                    in: realm)
        }
        reloadOutline()
        if let parent = item as? CPYFolder { outlineView.expandItem(parent) }
        // Selection is best-effort (the row map may not contain the moved item
        // if its ancestors aren't expanded). The right-hand pane is rendered
        // from the explicit identifier so it stays correct either way.
        selectRow(forItemID: dragged.identifier)
        changeItemFocus(forItemID: dragged.identifier)
        return true
    }
}

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
    static func move(itemId: String,
                     isFolder: Bool,
                     toParentId: String,
                     atIndex: Int,
                     visibleIDs: Set<String>? = nil,
                     in realm: Realm) {
        let oldParentId: String
        if isFolder {
            guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: itemId) else { return }
            oldParentId = folder.parentIdentifier
            folder.parentIdentifier = toParentId
        } else {
            guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: itemId) else { return }
            oldParentId = snippet.parentIdentifier
            snippet.parentIdentifier = toParentId
        }
        let allKids = CPYFolder.children(parentIdentifier: toParentId, in: realm)
        let target: Object?
        if isFolder {
            target = realm.object(ofType: CPYFolder.self, forPrimaryKey: itemId)
        } else {
            target = realm.object(ofType: CPYSnippet.self, forPrimaryKey: itemId)
        }
        let ordered: [Object]
        if let visible = visibleIDs {
            ordered = reorderRespectingHiddenAnchors(allKids: allKids,
                                                    visible: visible,
                                                    movedId: itemId,
                                                    movedItem: target,
                                                    atIndex: atIndex)
        } else {
            var working: [Object] = []
            for kid in allKids where idOf(kid) != itemId { working.append(kid) }
            if let target = target {
                let pos = (atIndex < 0 || atIndex > working.count) ? working.count : atIndex
                working.insert(target, at: pos)
            }
            ordered = working
        }
        for (idx, kid) in ordered.enumerated() {
            if let folder = kid as? CPYFolder { folder.index = idx }
            else if let snippet = kid as? CPYSnippet { snippet.index = idx }
        }
        if oldParentId != toParentId {
            CPYFolder.renumberSiblings(of: oldParentId, in: realm)
        }
    }

    /// Build the new full order while keeping every hidden sibling next to
    /// the same visible neighbour it had before. Each hidden sibling's
    /// "anchor" is the closest visible sibling that came before it in
    /// `allKids`; nil means it was before all visibles. After the moved
    /// item is repositioned within the visible subset, hidden siblings are
    /// re-emitted just after their anchor (or at the front for nil anchors).
    private static func reorderRespectingHiddenAnchors(allKids: [Object],
                                                       visible: Set<String>,
                                                       movedId: String,
                                                       movedItem: Object?,
                                                       atIndex: Int) -> [Object] {
        var hiddenByAnchor: [String: [Object]] = [:]
        var hiddenAtFront: [Object] = []
        var lastVisibleId: String?
        for kid in allKids {
            let kidId = idOf(kid)
            if visible.contains(kidId) {
                lastVisibleId = kidId
            } else {
                if let anchor = lastVisibleId {
                    hiddenByAnchor[anchor, default: []].append(kid)
                } else {
                    hiddenAtFront.append(kid)
                }
            }
        }
        var visibleOrdered: [Object] = []
        for kid in allKids where visible.contains(idOf(kid)) && idOf(kid) != movedId {
            visibleOrdered.append(kid)
        }
        if let movedItem = movedItem {
            let pos = (atIndex < 0 || atIndex > visibleOrdered.count) ? visibleOrdered.count : atIndex
            visibleOrdered.insert(movedItem, at: pos)
        }
        var result: [Object] = []
        result.append(contentsOf: hiddenAtFront)
        for kid in visibleOrdered {
            result.append(kid)
            if let trailing = hiddenByAnchor[idOf(kid)] {
                result.append(contentsOf: trailing)
            }
        }
        return result
    }

    private static func idOf(_ obj: Object) -> String {
        if let folder = obj as? CPYFolder { return folder.identifier }
        if let snippet = obj as? CPYSnippet { return snippet.identifier }
        return ""
    }
}
