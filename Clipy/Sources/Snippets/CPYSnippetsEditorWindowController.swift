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
        try? realm.write { realm.add(snippet) }
        reloadOutline()
        outlineView.expandItem(host)
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: snippet)), byExtendingSelection: false)
        changeItemFocus()
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
        try? realm.write { realm.add(folder) }
        reloadOutline()
        if let host = host { outlineView.expandItem(host) }
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
        changeItemFocus()
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
            let snippet = CPYSnippet()
            snippet.title = sEl[Constants.Xml.titleElement].value ?? "untitled snippet"
            snippet.content = sEl[Constants.Xml.contentElement].value ?? ""
            snippet.parentIdentifier = folder.identifier
            snippet.index = snippetIndex
            realm.add(snippet)
            snippetIndex += 1
        }
        var childIndex = 0
        element[Constants.Xml.foldersElement][Constants.Xml.folderElement].all?.forEach { childEl in
            importFolder(childEl, parentId: folder.identifier, index: childIndex, in: realm)
            childIndex += 1
        }
    }

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
        for snippet in snippets {
            let sEl = snippetsElement.addChild(name: Constants.Xml.snippetElement)
            sEl.addChild(name: Constants.Xml.titleElement, value: snippet.title)
            sEl.addChild(name: Constants.Xml.contentElement, value: snippet.content)
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

// MARK: - Item Selected
extension CPYSnippetsEditorWindowController {
    func changeItemFocus() {
        // Reset TextView Undo/Redo history
        textView.undoManager?.removeAllActions()
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            folderSettingView.isHidden = true
            textView.isHidden = true
            folderShortcutRecordView.keyCombo = nil
            folderTitleTextField.stringValue = ""
            return
        }
        if let folder = item as? CPYFolder {
            textView.string = ""
            folderTitleTextField.stringValue = folder.title
            folderShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folder.identifier)
            folderSettingView.isHidden = false
            textView.isHidden = true
        } else if let snippet = item as? CPYSnippet {
            textView.string = snippet.content
            folderTitleTextField.stringValue = ""
            folderShortcutRecordView.keyCombo = nil
            folderSettingView.isHidden = true
            textView.isHidden = false
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
        try? realm.write {
            if let folder = item as? CPYFolder { folder.title = text }
            else if let snippet = item as? CPYSnippet { snippet.title = text }
        }
        changeItemFocus()
        return true
    }
}

// MARK: - NSTextView Delegate
extension CPYSnippetsEditorWindowController: NSTextViewDelegate {
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
