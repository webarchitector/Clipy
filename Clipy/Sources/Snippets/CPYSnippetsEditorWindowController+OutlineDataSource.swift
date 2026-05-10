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
        // Stubbed in this commit; Task 6 of nested-snippets plan restores drag/drop with cycle and depth checks.
        return NSDragOperation()
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        // Stubbed in this commit; Task 6 of nested-snippets plan restores drag/drop with cycle and depth checks.
        return false
    }
}
