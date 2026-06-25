import Cocoa

// Driven entirely from the main thread (NSPanel UI), mirroring AppLauncher's
// concurrency model. @unchecked Sendable avoids an actor-isolation cascade
// through the AppKit delegate conformances we already serialize on main.
final class ScratchpadController: NSObject, NSSearchFieldDelegate,
                                  NSTableViewDataSource, NSTableViewDelegate, @unchecked Sendable {

    private enum Mode { case list, editor }

    private let store: ScratchpadStore
    private let copyToPasteboard: (String) -> Void
    private let hidePanel: () -> Void
    private let exitToRoot: () -> Void

    var onHeightChange: ((CGFloat) -> Void)?

    private weak var contentView: NSView?
    private weak var searchField: NSSearchField?
    private weak var launcherScroll: NSView?

    private var mode: Mode = .list
    private var notes: [CPYScratchNote] = []          // filtered list (excludes the "new" row)
    private var editingId: String?
    private var saveWorkItem: DispatchWorkItem?
    private var keyMonitor: Any?

    // List UI
    private var listScroll: NSScrollView?
    private var listTable: NSTableView?
    private var listBackButton: NSButton?
    // Editor UI
    private var editorScroll: NSScrollView?
    private var editorTextView: ScratchEditorTextView?
    private var editorBackButton: NSButton?

    private static let newRowTitle = "➕ New from clipboard"

    init(store: ScratchpadStore,
         copyToPasteboard: @escaping (String) -> Void,
         hidePanel: @escaping () -> Void,
         exitToRoot: @escaping () -> Void) {
        self.store = store
        self.copyToPasteboard = copyToPasteboard
        self.hidePanel = hidePanel
        self.exitToRoot = exitToRoot
    }

    // MARK: - Enter / leave

    func enter(contentView: NSView, searchField: NSSearchField, launcherScroll: NSView) {
        self.contentView = contentView
        self.searchField = searchField
        self.launcherScroll = launcherScroll
        launcherScroll.isHidden = true
        searchField.stringValue = ""
        searchField.placeholderString = "Search scratchpad…"
        searchField.delegate = self
        showList(filter: "")

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.mode == .list else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command, event.charactersIgnoringModifiers == "c" {
                if let row = self.listTable?.selectedRow, row > 0, row - 1 < self.notes.count {
                    self.copyToPasteboard(self.notes[row - 1].content)
                    self.hidePanel()
                    return nil
                }
            }
            return event
        }
    }

    func leave() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        teardownList()
        teardownEditor()
        launcherScroll?.isHidden = false
        searchField?.isHidden = false
        searchField?.placeholderString = "App, math (`(1+2)=`), or currency (`15 usd thb=`)"
    }

    // MARK: - List

    private func showList(filter: String) {
        mode = .list
        teardownEditor()
        searchField?.isHidden = false
        reloadNotes(filter: filter)

        guard let contentView = contentView, let field = searchField else { return }
        if listScroll == nil {
            let backButton = makeBackButton(title: "← Apps", action: #selector(backToApps))
            contentView.addSubview(backButton)

            let table = NSTableView()
            table.dataSource = self
            table.delegate = self
            table.headerView = nil
            table.rowHeight = 24
            table.style = .plain
            table.intercellSpacing = NSSize(width: 0, height: 2)
            table.target = self
            table.action = #selector(listRowClicked)
            table.doubleAction = #selector(listRowClicked)
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("scratch"))
            col.width = 580
            table.addTableColumn(col)

            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.borderType = .noBorder
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(scroll)
            NSLayoutConstraint.activate([
                backButton.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
                backButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
                scroll.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 6),
                scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
                scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
                scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
            ])
            self.listScroll = scroll
            self.listTable = table
            self.listBackButton = backButton
        }
        listScroll?.isHidden = false
        listBackButton?.isHidden = false
        listTable?.reloadData()
        if (listTable?.numberOfRows ?? 0) > 0 {
            listTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        // Keep the search field first responder in list mode so ↑/↓ reach
        // control(_:textView:doCommandBy:) (the field editor delivers them).
        // Without this, returning from the editor leaves focus on the removed
        // text view and arrow keys do nothing.
        field.window?.makeFirstResponder(field)
        emitHeight(rows: notes.count + 1)
    }

    private func reloadNotes(filter: String) {
        let all = store.allNotes()
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        notes = query.isEmpty ? all : all.filter { $0.content.lowercased().contains(query) }
    }

    private func teardownList() {
        listScroll?.removeFromSuperview()
        listBackButton?.removeFromSuperview()
        listScroll = nil
        listTable = nil
        listBackButton = nil
    }

    private func makeBackButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func backToApps() {
        exitToRoot()
    }

    @objc private func backToList() {
        saveAndShowList()
    }

    @objc private func listRowClicked() {
        activateListSelection()
    }

    func activateListSelection() {
        guard let row = listTable?.selectedRow, row >= 0 else { return }
        if row == 0 {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            if let newID = store.create(content: clip) { openEditor(id: newID) }
            return
        }
        let noteIndex = row - 1
        guard noteIndex < notes.count else { return }
        openEditor(id: notes[noteIndex].identifier)
    }

    func moveListSelection(by delta: Int) {
        guard let table = listTable else { return }
        let count = table.numberOfRows
        guard count > 0 else { return }
        var next = table.selectedRow + delta
        next = max(0, min(count - 1, next))
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    private func deleteSelectedFromList() {
        guard let row = listTable?.selectedRow, row > 0 else { return }
        let index = row - 1
        guard index < notes.count else { return }
        store.delete(id: notes[index].identifier)
        reloadNotes(filter: searchField?.stringValue ?? "")
        listTable?.reloadData()
        emitHeight(rows: notes.count + 1)
    }

    // MARK: - Editor

    private func openEditor(id noteID: String) {
        mode = .editor
        editingId = noteID
        teardownList()
        searchField?.isHidden = true

        guard let contentView = contentView else { return }
        let textView = ScratchEditorTextView()
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.string = store.note(id: noteID)?.content ?? ""
        textView.delegate = self
        textView.onCancel = { [weak self] in self?.saveAndShowList() }
        textView.onCommandEnter = { [weak self] in self?.copyCurrentAndHide() }
        textView.onDeleteNote = { [weak self] in self?.deleteCurrentAndShowList() }

        let backButton = makeBackButton(title: "← List", action: #selector(backToList))
        contentView.addSubview(backButton)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scroll)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
        self.editorScroll = scroll
        self.editorTextView = textView
        self.editorBackButton = backButton
        contentView.window?.makeFirstResponder(textView)
    }

    private func teardownEditor() {
        flushEditorSave()
        editorScroll?.removeFromSuperview()
        editorBackButton?.removeFromSuperview()
        editorScroll = nil
        editorTextView = nil
        editorBackButton = nil
    }

    private func flushEditorSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard let noteID = editingId, let textView = editorTextView else { return }
        store.update(id: noteID, content: textView.string)
    }

    private func saveAndShowList() {
        flushEditorSave()
        editingId = nil
        showList(filter: "")
    }

    private func copyCurrentAndHide() {
        flushEditorSave()
        if let textView = editorTextView { copyToPasteboard(textView.string) }
        hidePanel()
    }

    private func deleteCurrentAndShowList() {
        if let noteID = editingId { store.delete(id: noteID) }
        editingId = nil
        teardownEditor()
        showList(filter: "")
    }

    // MARK: - Height

    func emitHeight(rows: Int) {
        let rowHeight: CGFloat = 24 + 2
        let chrome: CGFloat = 8 + 28 + 6 + 8
        onHeightChange?(chrome + CGFloat(max(1, rows)) * rowHeight + 4)
    }

    // Routed from control(_:textView:doCommandBy:) so the Escape behaviour lives
    // next to the rest of the list logic.
    func handleListCancel() {
        if !(searchField?.stringValue.isEmpty ?? true) {
            searchField?.stringValue = ""
            controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        } else {
            exitToRoot()
        }
    }

    func deleteSelectedNoteFromList() {
        deleteSelectedFromList()
    }
}

// MARK: - NSTableView data source / delegate (list)

extension ScratchpadController {
    func numberOfRows(in tableView: NSTableView) -> Int { notes.count + 1 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("scratchCell"), owner: self)
                    as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("scratchCell")
        let label = cell.textField ?? {
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return field
        }()
        label.font = NSFont.systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        if row == 0 {
            label.stringValue = Self.newRowTitle
            label.textColor = .secondaryLabelColor
        } else {
            let note = notes[row - 1]
            let title = ScratchTitle.title(from: note.content)
            label.stringValue = title.isEmpty ? "Empty note" : title
            label.textColor = .labelColor
        }
        return cell
    }
}

// MARK: - NSSearchFieldDelegate (list filtering + keys)

extension ScratchpadController {
    func controlTextDidChange(_ obj: Notification) {
        guard mode == .list else { return }
        reloadNotes(filter: searchField?.stringValue ?? "")
        listTable?.reloadData()
        if (listTable?.numberOfRows ?? 0) > 0 {
            listTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        emitHeight(rows: notes.count + 1)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard mode == .list else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            activateListSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            handleListCancel()
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveListSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveListSelection(by: -1)
            return true
        case #selector(NSResponder.deleteToBeginningOfLine(_:)):
            deleteSelectedNoteFromList()
            return true
        default:
            return false
        }
    }
}

// MARK: - NSTextViewDelegate (editor autosave)

extension ScratchpadController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard mode == .editor else { return }
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushEditorSave() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400), execute: work)
    }
}
