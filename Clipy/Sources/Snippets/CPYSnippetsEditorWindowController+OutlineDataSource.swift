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

// MARK: - NSOutlineView DataSource
extension CPYSnippetsEditorWindowController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return Int(folders.count)
        } else if let folder = item as? CPYFolder {
            return Int(folder.snippets.count)
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let folder = item as? CPYFolder {
            return !folder.snippets.isEmpty
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return folders[index]
        } else if let folder = item as? CPYFolder {
            return folder.snippets[index]
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        if let folder = item as? CPYFolder {
            return folder.title
        } else if let snippet = item as? CPYSnippet {
            return snippet.title
        }
        return ""
    }

    // MARK: - Drag and Drop
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

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return NSDragOperation() }
        guard let draggedData = LegacyKeyedArchive.unarchivedObject(of: CPYDraggedData.self, from: data) else { return NSDragOperation() }

        switch draggedData.type {
        case .folder where item == nil:
            return .move
        case .snippet where item is CPYFolder:
            return .move
        default:
            return NSDragOperation()
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return false }
        guard let draggedData = LegacyKeyedArchive.unarchivedObject(of: CPYDraggedData.self, from: data) else { return false }

        switch draggedData.type {
        case .folder where index != draggedData.index:
            guard index >= 0 else { return false }
            guard let folder = folders.first(where: { $0.identifier == draggedData.identifier }) else { return false }
            folders.insert(folder, at: index)
            let removedIndex = (index < draggedData.index) ? draggedData.index + 1 : draggedData.index
            folders.remove(at: removedIndex)
            outlineView.reloadData()
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
            CPYFolder.rearrangesIndex(folders)
            changeItemFocus()
            return true
        case .snippet:
            guard let fromFolder = folders.first(where: { $0.identifier == draggedData.parentIdentifier }) else { return false }
            guard let toFolder = item as? CPYFolder else { return false }
            guard let snippet = fromFolder.snippets.first(where: { $0.identifier == draggedData.identifier }) else { return false }

            if fromFolder.identifier == toFolder.identifier {
                guard index >= 0 else { return false }
                if index == draggedData.index { return false }
                // Move to same folder
                fromFolder.snippets.insert(snippet, at: index)
                let removedIndex = (index < draggedData.index) ? draggedData.index + 1 : draggedData.index
                fromFolder.snippets.remove(at: removedIndex)
                outlineView.reloadData()
                outlineView.selectRowIndexes(NSIndexSet(index: outlineView.row(forItem: snippet)) as IndexSet, byExtendingSelection: false)
                fromFolder.rearrangesSnippetIndex()
                changeItemFocus()
                return true
            } else {
                // Move to other folder
                let index = max(0, index)
                toFolder.snippets.insert(snippet, at: index)
                fromFolder.snippets.remove(at: draggedData.index)
                outlineView.reloadData()
                outlineView.expandItem(toFolder)
                outlineView.selectRowIndexes(NSIndexSet(index: outlineView.row(forItem: snippet)) as IndexSet, byExtendingSelection: false)
                toFolder.insertSnippet(snippet, index: index)
                fromFolder.removeSnippet(snippet)
                changeItemFocus()
                return true
            }
        default: return false
        }
    }
}
