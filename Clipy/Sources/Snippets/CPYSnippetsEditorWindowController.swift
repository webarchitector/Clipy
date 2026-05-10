//
//  CPYSnippetsEditorWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/05/18.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RealmSwift
// See CPYShortcutsPreferenceViewController for why @preconcurrency.
@preconcurrency import KeyHolder
import UniformTypeIdentifiers
import Magnet
import AEXML

final class CPYSnippetsEditorWindowController: NSWindowController {

    // MARK: - Properties
    static let sharedController = CPYSnippetsEditorWindowController(windowNibName: "CPYSnippetsEditorWindowController")
    @IBOutlet private weak var splitView: CPYSplitView!
    @IBOutlet private weak var folderSettingView: NSView!
    @IBOutlet private weak var folderTitleTextField: NSTextField!
    @IBOutlet private weak var folderShortcutRecordView: RecordView! {
        didSet {
            folderShortcutRecordView.delegate = self
        }
    }
    @IBOutlet private var textView: CPYPlaceHolderTextView! {
        didSet {
            textView.font = NSFont.systemFont(ofSize: 14)
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.enabledTextCheckingTypes = 0
            textView.isRichText = false
            textView.placeHolderText = L10n.pleaseFillInTheContentsOfTheSnippet
        }
    }
    @IBOutlet private weak var outlineView: NSOutlineView! {
        didSet {
            // Enable Drag and Drop
            outlineView.registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)])
        }
    }
    @IBOutlet private weak var searchField: NSSearchField!

    /// Cache of `(parentIdentifier → children)` for the outline view's data source
    /// methods. Invalidated by `reloadOutline()` before every reload.
    private var childrenCache: [String: [Object]] = [:]

    /// When non-nil, the outline view is filtered: only IDs in the set are
    /// rendered, and ancestor folders of matched snippets are auto-expanded.
    /// nil means no filter (full tree visible).
    private var visibleIdentifiers: Set<String>?

    /// Folder IDs that were expanded when the user first entered search mode
    /// (`visibleIdentifiers` transitioned nil → non-nil). Used to restore the
    /// pre-search expansion state when the query is cleared.
    private var savedExpandedIDs: Set<String>?

    /// Identifier (CPYFolder or CPYSnippet primary key) currently rendered in the
    /// right-hand pane. Source of truth for "what is the user looking at?". Updated
    /// only by `changeItemFocus`; consulted by the textView write path to refuse
    /// edits that would land on a different snippet than the one the user sees.
    private var displayedItemID: String?

    func children(parentId: String) -> [Object] {
        if let cached = childrenCache[parentId] { return cached }
        guard let realm = Realm.safeInstance() else { return [] }
        var kids = CPYFolder.children(parentIdentifier: parentId, in: realm)
        if let visible = visibleIdentifiers {
            kids = kids.filter { visible.contains(CPYFolder.nodeID(of: $0)) }
        }
        childrenCache[parentId] = kids
        return kids
    }

    /// Returns the controller's current visible-id filter set. Exposed for
    /// `NestedMoveExecutor` so drag-drop honours hidden siblings (Task 4).
    func visibleIdentifiersForMove() -> Set<String>? {
        return visibleIdentifiers
    }

    func reloadOutline() {
        childrenCache.removeAll()
        // When a filter is active, refresh the visible-id set against the
        // current Realm state. Without this, deletes leave stale IDs in the
        // set and moves can drop visible items from the rendered tree.
        if visibleIdentifiers != nil, let realm = Realm.safeInstance() {
            visibleIdentifiers = SnippetSearchFilter.visibleIdentifiers(query: searchField.stringValue, in: realm)
        }
        outlineView.reloadData()
    }

    /// Drop any active filter (search field text, visible-id set, expansion
    /// snapshot). Used after `addSnippet`/`addFolder` so a freshly created
    /// item is not hidden by a no-longer-relevant query — the user clearly
    /// wants to see what they just made.
    private func clearActiveFilter() {
        guard visibleIdentifiers != nil else { return }
        searchField.stringValue = ""
        visibleIdentifiers = nil
        savedExpandedIDs = nil
    }

    private var selectedSnippet: CPYSnippet? {
        guard let snippet = outlineView.item(atRow: outlineView.selectedRow) as? CPYSnippet else { return nil }
        return snippet
    }

    /// The folder that should host new snippets/subfolders for the current selection.
    /// If a folder is selected → that folder. If a snippet is selected → its parent
    /// folder (looked up by `parentIdentifier`). If nothing is selected → nil.
    private var selectedHostFolder: CPYFolder? {
        guard let realm = Realm.safeInstance() else { return nil }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
        if let folder = item as? CPYFolder { return folder }
        if let snippet = item as? CPYSnippet, !snippet.parentIdentifier.isEmpty {
            return realm.object(ofType: CPYFolder.self, forPrimaryKey: snippet.parentIdentifier)
        }
        return nil
    }

    // MARK: - Window Life Cycle
    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.collectionBehavior = NSWindow.CollectionBehavior.canJoinAllSpaces
        self.window?.backgroundColor = .windowBackgroundColor
        self.window?.titlebarAppearsTransparent = true
        splitView.separatorColor = .separatorColor
        outlineView.backgroundColor = .controlBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.placeHolderColor = .placeholderTextColor
        folderShortcutRecordView.tintColor = .controlAccentColor
        folderShortcutRecordView.borderColor = .separatorColor
        CPYUtilities.applyAdaptiveAppearance(to: window?.contentView)
        outlineView.target = self
        outlineView.action = #selector(outlineViewClicked(_:))
        searchField.placeholderString = L10n.searchSnippets
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.delegate = self
        reloadOutline()
        // Select first root folder
        if let realm = Realm.safeInstance(),
           let firstRoot = realm.objects(CPYFolder.self)
               .filter("parentIdentifier == ''")
               .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
               .first {
            selectRow(forItemID: firstRoot.identifier)
            changeItemFocus(forItemID: firstRoot.identifier)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.backgroundColor = .windowBackgroundColor
        // Weak outlets can be nil on re-open if AppKit tore the view hierarchy down between showings.
        splitView?.separatorColor = .separatorColor
        folderShortcutRecordView?.tintColor = .controlAccentColor
        folderShortcutRecordView?.borderColor = .separatorColor
        CPYUtilities.applyAdaptiveAppearance(to: window?.contentView)
        CPYUtilities.presentSnippetsWindow(window)
    }
}

// MARK: - IBActions
extension CPYSnippetsEditorWindowController {
    @IBAction private func addSnippetButtonTapped(_ sender: AnyObject) {
        guard let realm = Realm.safeInstance() else { NSSound.beep(); return }
        guard let host = selectedHostFolder else { NSSound.beep(); return }
        let snippet = CPYSnippet()
        snippet.title = "untitled snippet"
        snippet.parentIdentifier = host.identifier
        snippet.index = children(parentId: host.identifier).count
        let snippetID = snippet.identifier
        try? realm.write { realm.add(snippet) }
        clearActiveFilter()
        reloadOutline()
        outlineView.expandItem(host)
        selectRow(forItemID: snippetID)
        changeItemFocus(forItemID: snippetID)
    }

    @IBAction private func addFolderButtonTapped(_ sender: AnyObject) {
        guard let realm = Realm.safeInstance() else { NSSound.beep(); return }
        let host: CPYFolder? = selectedHostFolder
        if let host = host, CPYFolder.depth(of: host, in: realm) >= 5 {
            NSSound.beep(); return
        }
        let folder = CPYFolder()
        folder.title = "untitled folder"
        folder.parentIdentifier = host?.identifier ?? ""
        folder.index = children(parentId: folder.parentIdentifier).count
        let folderID = folder.identifier
        try? realm.write { realm.add(folder) }
        clearActiveFilter()
        reloadOutline()
        if let host = host { outlineView.expandItem(host) }
        selectRow(forItemID: folderID)
        changeItemFocus(forItemID: folderID)
    }

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
        while let current = stack.popLast() {
            let subs = realm.objects(CPYFolder.self).filter("parentIdentifier == %@", current.identifier)
            for sub in subs {
                idsToUnregister.append(sub.identifier)
                stack.append(sub)
            }
        }
        // Delete descendants bottom-up: snippets, then folders.
        for fid in idsToUnregister {
            let snippets = realm.objects(CPYSnippet.self).filter("parentIdentifier == %@", fid)
            realm.delete(snippets)
        }
        let parentId = folder.parentIdentifier
        for fid in idsToUnregister.reversed() {
            if let descendant = realm.object(ofType: CPYFolder.self, forPrimaryKey: fid) {
                realm.delete(descendant)
            }
        }
        // Unregister hotkeys for every removed folder.
        for fid in idsToUnregister {
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: fid)
        }
        CPYFolder.renumberSiblings(of: parentId, in: realm)
    }

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
}

// MARK: - Item Selected
extension CPYSnippetsEditorWindowController {
    /// Refresh the right-hand pane to reflect either an explicitly named item
    /// (`forItemID`) or, if nil, whatever the outline view currently reports as
    /// selected. The explicit form is the defensive entry point used after
    /// mutations (add / delete / drag-drop) where the outline view's row→item
    /// map may briefly disagree with the Realm state we just wrote — passing
    /// the identifier directly bypasses any stale row lookup. Always re-fetches
    /// the live Realm object by primary key, then records the displayed ID in
    /// `displayedItemID` so the textView write path can refuse edits aimed at a
    /// different snippet than the one on screen.
    func changeItemFocus(forItemID: String? = nil) {
        textView.undoManager?.removeAllActions()
        let id = forItemID ?? selectedItemIdentifier()
        guard let id = id, let realm = Realm.safeInstance() else {
            renderEmptyFocus()
            return
        }
        if let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: id) {
            textView.string = ""
            folderTitleTextField.stringValue = folder.title
            folderShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folder.identifier)
            folderSettingView.isHidden = false
            textView.isHidden = true
            displayedItemID = id
        } else if let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: id) {
            textView.string = snippet.content
            folderTitleTextField.stringValue = ""
            folderShortcutRecordView.keyCombo = nil
            folderSettingView.isHidden = true
            textView.isHidden = false
            displayedItemID = id
        } else {
            renderEmptyFocus()
        }
    }

    private func renderEmptyFocus() {
        folderSettingView.isHidden = true
        textView.isHidden = true
        folderShortcutRecordView.keyCombo = nil
        folderTitleTextField.stringValue = ""
        textView.string = ""
        displayedItemID = nil
    }

    private func selectedItemIdentifier() -> String? {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
        if let folder = item as? CPYFolder { return folder.identifier }
        if let snippet = item as? CPYSnippet { return snippet.identifier }
        return nil
    }

    /// Best-effort row selection by item identifier. Walks the outline view's
    /// row→item map (`row(forItem:)` returns -1 if the item is not currently
    /// laid out — e.g., its ancestors aren't expanded). When that happens we
    /// silently skip the AppKit selection step; the right-hand pane is still
    /// rendered correctly via `changeItemFocus(forItemID:)` in the caller.
    @discardableResult
    func selectRow(forItemID id: String) -> Bool {
        guard let realm = Realm.safeInstance() else { return false }
        let item: Any? = realm.object(ofType: CPYFolder.self, forPrimaryKey: id) as Any?
            ?? realm.object(ofType: CPYSnippet.self, forPrimaryKey: id) as Any?
        guard let item = item else { return false }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return false }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        return true
    }

    @objc func outlineViewClicked(_ sender: Any?) {
        // Force a refresh even when selection didn't change (clicking the
        // currently-selected row). Defensive against any state where the
        // textView fell out of sync with the actual selection.
        changeItemFocus()
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        applyFilter(sender.stringValue)
    }

    @IBAction func findInSnippets(_ sender: Any?) {
        window?.makeFirstResponder(searchField)
    }

    private func applyFilter(_ query: String) {
        guard let realm = Realm.safeInstance() else { return }
        let new = SnippetSearchFilter.visibleIdentifiers(query: query, in: realm)
        let wasNil = (visibleIdentifiers == nil)
        let willBeNil = (new == nil)
        let previouslySelectedID = selectedItemIdentifier()

        if wasNil && !willBeNil {
            savedExpandedIDs = collectExpandedFolderIDs()
        }
        visibleIdentifiers = new
        reloadOutline()

        if !willBeNil {
            expandAllVisibleFolders()
        } else if let saved = savedExpandedIDs {
            outlineView.collapseItem(nil, collapseChildren: true)
            for id in saved {
                if let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: id) {
                    outlineView.expandItem(folder)
                }
            }
            savedExpandedIDs = nil
        }

        restoreSelectionAfterFilter(previouslySelectedID: previouslySelectedID)
    }

    private func collectExpandedFolderIDs() -> Set<String> {
        var ids = Set<String>()
        for row in 0..<outlineView.numberOfRows {
            guard let folder = outlineView.item(atRow: row) as? CPYFolder else { continue }
            if outlineView.isItemExpanded(folder) {
                ids.insert(folder.identifier)
            }
        }
        return ids
    }

    private func expandAllVisibleFolders() {
        guard let visible = visibleIdentifiers else { return }
        guard let realm = Realm.safeInstance() else { return }
        for id in visible {
            if let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: id) {
                outlineView.expandItem(folder)
            }
        }
    }

    private func restoreSelectionAfterFilter(previouslySelectedID: String?) {
        if let id = previouslySelectedID, selectRow(forItemID: id) {
            changeItemFocus(forItemID: id)
            return
        }
        if outlineView.numberOfRows > 0 {
            outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            changeItemFocus()
        } else {
            outlineView.deselectAll(nil)
            changeItemFocus()
        }
    }
}


// MARK: - NSSplitView Delegate
extension CPYSnippetsEditorWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMinimumPosition + 150
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMaximumPosition / 2
    }
}

// MARK: - NSOutlineView Delegate
extension CPYSnippetsEditorWindowController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, item: Any) {
        guard let cell = cell as? CPYSnippetsEditorCell else { return }
        if let folder = item as? CPYFolder {
            cell.iconType = .folder
            cell.isItemEnabled = folder.enable
        } else if let snippet = item as? CPYSnippet {
            cell.iconType = .none
            cell.isItemEnabled = snippet.enable
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        changeItemFocus()
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        let text = fieldEditor.string
        guard !text.isEmpty else { return false }
        guard let outlineView = control as? NSOutlineView else { return false }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return false }
        guard let realm = Realm.safeInstance() else { return false }
        let itemID: String
        if let folder = item as? CPYFolder { itemID = folder.identifier }
        else if let snippet = item as? CPYSnippet { itemID = snippet.identifier }
        else { return false }
        try? realm.write {
            if let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: itemID) {
                folder.title = text
            } else if let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: itemID) {
                snippet.title = text
            }
        }
        changeItemFocus(forItemID: itemID)
        return true
    }
}

// MARK: - NSTextView Delegate
extension CPYSnippetsEditorWindowController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString = replacementString else { return false }
        guard let snippet = selectedSnippet else { return false }
        // Defense against textView/selection desync: if the snippet currently
        // in the right pane is not the snippet the outline view reports as
        // selected, we'd be writing the user's keystroke into the wrong row.
        // Refuse the write and resync instead — the user's input is dropped
        // (one keystroke), but no data corruption occurs.
        guard SnippetEditorSelectionGuard.writeIsSafe(displayedID: displayedItemID,
                                                      selectedID: snippet.identifier) else {
            changeItemFocus()
            return false
        }
        let text = textView.string
        guard let realm = Realm.safeInstance() else { return false }
        guard let range = Range(affectedCharRange, in: text) else { return false }
        var string = text
        string.replaceSubrange(range, with: replacementString)
        try? realm.write { snippet.content = string }
        return true
    }
}

// MARK: - NSSearchFieldDelegate
extension CPYSnippetsEditorWindowController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if !searchField.stringValue.isEmpty {
                searchField.stringValue = ""
                applyFilter("")
            } else {
                window?.makeFirstResponder(outlineView)
            }
            return true
        }
        return false
    }
}

// MARK: - NSWindow Delegate
extension CPYSnippetsEditorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        CPYUtilities.closeSnippetsWindow()
    }
}

// MARK: - RecordView Delegate
// See CPYShortcutsPreferenceViewController for why @preconcurrency.
@MainActor extension CPYSnippetsEditorWindowController: @preconcurrency RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        guard selectedHostFolder != nil else { return false }
        return true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        guard selectedHostFolder != nil else { return false }
        return true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        guard let selectedHostFolder = selectedHostFolder else { return }
        guard let keyCombo = keyCombo else {
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: selectedHostFolder.identifier)
            return
        }
        AppEnvironment.current.hotKeyService.registerSnippetHotKey(with: selectedHostFolder.identifier, keyCombo: keyCombo)
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
