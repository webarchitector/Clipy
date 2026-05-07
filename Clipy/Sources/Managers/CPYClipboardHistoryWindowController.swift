//
//  CPYClipboardHistoryWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//

import Cocoa
import Quartz
import RealmSwift

// MARK: - Data Model

struct ClipboardHistoryEntry: Equatable {
    let primaryKey: String
    let displayTitle: String
    let searchText: String
    let toolTip: String
    let thumbnailPath: String
    let isColorCode: Bool
    let dataPath: String
    let primaryType: String
    let updateTime: Int
    let isPinned: Bool
    let sourceBundleID: String

    init(clip: CPYClip) {
        primaryKey = clip.dataHash
        thumbnailPath = clip.thumbnailPath
        isColorCode = clip.isColorCode
        dataPath = clip.dataPath
        primaryType = clip.primaryType
        updateTime = clip.updateTime
        isPinned = clip.isPinned
        sourceBundleID = clip.sourceBundleID

        // Use title stored in Realm (already contains preferredTitle from ClipService.save)
        let clipTitle = ClipboardHistoryEntry.sanitizedStoredTitle(clip.title)

        let rawTitle: String
        if clipTitle.isEmpty {
            rawTitle = ClipboardHistoryEntry.fallbackTitle(for: clip)
        } else {
            rawTitle = clipTitle
        }
        // Collapse runs of whitespace/newlines into a single space and trim — single pass.
        displayTitle = ClipboardHistoryEntry.collapseWhitespace(rawTitle, maxScalars: 500)

        searchText = displayTitle
        toolTip = displayTitle.count <= 2000 ? displayTitle : String(displayTitle.prefix(2000))
    }

    private static func collapseWhitespace(_ input: String, maxScalars: Int) -> String {
        let whitespaceAndNewlines = CharacterSet.whitespacesAndNewlines
        var output = ""
        output.reserveCapacity(min(input.utf8.count, maxScalars))
        var count = 0
        var lastWasSpace = true
        for scalar in input.unicodeScalars {
            if count >= maxScalars { break }
            if whitespaceAndNewlines.contains(scalar) {
                if !lastWasSpace {
                    output.unicodeScalars.append(" ")
                    count += 1
                    lastWasSpace = true
                }
            } else {
                output.unicodeScalars.append(scalar)
                count += 1
                lastWasSpace = false
            }
        }
        if output.unicodeScalars.last == " " {
            output.unicodeScalars.removeLast()
        }
        return output
    }

    private static func fallbackTitle(for clip: CPYClip) -> String {
        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipTitle = sanitizedStoredTitle(clip.title)
        if !clipTitle.isEmpty {
            return clipTitle
        }

        switch primaryPboardType {
        case .deprecatedTIFF, .tiff, .png:
            return "(Image)"
        case .deprecatedPDF, .pdf:
            return "(PDF)"
        case .deprecatedFilenames, .fileURL:
            return "(File)"
        case .deprecatedURL, .URL:
            return "(URL)"
        default:
            return ""
        }
    }

    private static func sanitizedStoredTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !["(Text)", "(Filenames)"].contains(trimmedTitle) else { return "" }
        return trimmedTitle
    }
}

// MARK: - Panel

/// NSPanel subclass that wires panel-level key equivalents:
/// - Cmd+O / Cmd+О → open the selected entry in the default app
/// - Cmd+1…9 / Cmd+0 → confirm the Nth visible entry (0 = 10th)
///
/// Both fire regardless of whether the search field or the table view is
/// the first responder, so the user can quick-paste straight after
/// hitting the history hotkey without ever moving focus.
final class ClipboardHistoryPanel: NSPanel {
    var openInDefaultAppHandler: (() -> Void)?
    var quickPasteHandler: ((Int) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard mods == .command, let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        if chars == "o" || chars == "о" {
            openInDefaultAppHandler?()
            return true
        }
        // Cmd+1…9 → row index 0…8; Cmd+0 → row index 9. Matches the original
        // NSMenu behaviour of `addNumericKeyEquivalents` so muscle memory
        // carries over when users switch between menu and history window.
        if let digit = Int(chars), (0...9).contains(digit) {
            let index = (digit == 0) ? 9 : digit - 1
            quickPasteHandler?(index)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Table View

final class ClipboardHistoryTableView: NSTableView {
    var confirmHandler: (() -> Void)?
    var cancelHandler: (() -> Void)?
    var openInDefaultAppHandler: (() -> Void)?
    var quickLookHandler: (() -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        super.mouseDown(with: event)

        guard event.clickCount == 1 else { return }
        guard clickedRow >= 0, selectedRow == clickedRow else { return }
        confirmHandler?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            confirmHandler?()
            return
        case 53:
            cancelHandler?()
            return
        case 49:  // space — Quick Look toggle
            quickLookHandler?()
            return
        default:
            break
        }
        // Vim-style j/k navigation when the table has focus. Russian-layout
        // aliases (о/л) are honored so muscle memory survives a layout
        // switch — same pattern as the panel's Cmd+O / Cmd+О binding.
        // Search-field input is unaffected: when the search field is the
        // first responder, this method never fires.
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods.isEmpty, let chars = event.charactersIgnoringModifiers?.lowercased() {
            if chars == "j" || chars == "о" {
                moveSelection(by: 1)
                return
            }
            if chars == "k" || chars == "л" {
                moveSelection(by: -1)
                return
            }
        }
        // Bare 'o' is *not* an Open-in-Default-App shortcut: it'd swallow
        // type-to-search and bare-letter typing that users expect from a
        // table view. The only Open-in-Default-App entry point is Cmd+O,
        // captured at the panel level via performKeyEquivalent.
        super.keyDown(with: event)
    }

    private func moveSelection(by delta: Int) {
        let count = numberOfRows
        guard count >= 1 else { return }
        let current = selectedRow
        let target: Int
        if current < 0 {
            target = delta > 0 ? 0 : count - 1
        } else {
            target = max(0, min(count - 1, current + delta))
        }
        selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        scrollRowToVisible(target)
    }

    // Build the menu per-event from the click location. Returning nil for
    // empty rows / non-openable types keeps the panel key (an empty NSMenu
    // would briefly resign-key the panel during AppKit's display dance).
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else { return nil }
        // Mirror Finder/Mail UX: right-click selects the row before showing
        // the context menu so the action's target is unambiguous.
        selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        return contextMenuProvider?(clickedRow)
    }
}

// MARK: - Window Controller

final class CPYClipboardHistoryWindowController: NSWindowController {
    static let sharedController = CPYClipboardHistoryWindowController()

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = ClipboardHistoryTableView()
    private let emptyStateLabel = NSTextField(labelWithString: L10n.noMatchingHistoryItems)
    private let historyPreviewView = HistoryPreviewView()
    private var realm: Realm? = Realm.safeInstance()

    private var clipToken: NotificationToken?
    private var workspaceObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var entries = [ClipboardHistoryEntry]()
    private var filteredEntries = [ClipboardHistoryEntry]()
    private var returnApplication: NSRunningApplication?
    private var isWindowVisible = false
    private var pendingReload = false
    private var reloadWorkItem: DispatchWorkItem?
    // Mirrors the menu's preview settings (Show Image / Show color preview /
    // Show tool tip / Show icon / max tooltip length) so the cell view honors
    // the same Preferences > Menu toggles. Refreshed on didChange.
    private var settings = MenuSettings()

    init() {
        // NSPanel (not NSWindow) so showing the history doesn't require
        // flipping the app to .regular activation policy — that switch is
        // synchronously gated by TCC and stalls visibly when Accessibility
        // is denied. The panel can still become key via NSApp.activate.
        let panel = ClipboardHistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
                                          styleMask: [.titled, .closable, .resizable],
                                          backing: .buffered,
                                          defer: false)
        super.init(window: panel)
        panel.openInDefaultAppHandler = { [weak self] in
            self?.openSelectedInDefaultApp()
        }
        panel.quickPasteHandler = { [weak self] index in
            self?.quickPaste(at: index)
        }
        configureWindow()
        configureContentView()
        observeWorkspace()
        observeClips()
        observeDefaults()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // No deinit cleanup: this is a `static let sharedController` singleton
    // that lives for the process lifetime. Realm NotificationToken auto-
    // invalidates with the Realm; block-based NSWorkspace / NotificationCenter
    // observers auto-release on shutdown. Swift 6's nonisolated deinit can't
    // touch main-actor properties anyway, and a Task hop here would race
    // with process teardown.

    override func showWindow(_ sender: Any?) {
        rememberReturnApplication(NSWorkspace.shared.frontmostApplication)
        searchField.stringValue = ""
        isWindowVisible = true
        pendingReload = false
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        settings = MenuSettings()
        tableView.rowHeight = computedRowHeight()
        reloadEntries()
        super.showWindow(sender)
        window?.backgroundColor = .windowBackgroundColor
        // Direct activate — no setActivationPolicy(.regular), which is the
        // path that lags hard without Accessibility (see init() comment).
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(searchField)
    }
}

// MARK: - Configuration

private extension CPYClipboardHistoryWindowController {
    func configureWindow() {
        window?.title = L10n.history
        window?.delegate = self
        window?.backgroundColor = .windowBackgroundColor
        window?.collectionBehavior = .canJoinAllSpaces
        window?.minSize = NSSize(width: 420, height: 320)
        window?.setFrameAutosaveName("CPYClipboardHistoryWindow")
        window?.center()
    }

    func configureContentView() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = L10n.searchHistory
        searchField.delegate = self

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        tableColumn.resizingMask = .autoresizingMask
        tableColumn.width = 480

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = computedRowHeight()
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .controlBackgroundColor
        tableView.focusRingType = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(confirmSelection(_:))
        tableView.confirmHandler = { [weak self] in
            self?.confirmSelection(nil)
        }
        tableView.cancelHandler = { [weak self] in
            self?.close()
        }
        tableView.openInDefaultAppHandler = { [weak self] in
            self?.openSelectedInDefaultApp()
        }
        tableView.quickLookHandler = { [weak self] in
            self?.toggleQuickLook()
        }
        tableView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(forRow: row)
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        scrollView.documentView = tableView

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.isHidden = true

        // Build a horizontal NSSplitView: history list on the left, full
        // preview of the selected clip on the right. The user can drag the
        // divider; min widths keep both panes usable.
        let listSide = NSView()
        listSide.translatesAutoresizingMaskIntoConstraints = false
        listSide.addSubview(scrollView)
        listSide.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: listSide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: listSide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listSide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listSide.bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 16),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -16)
        ])

        historyPreviewView.translatesAutoresizingMaskIntoConstraints = false

        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.identifier = NSUserInterfaceItemIdentifier("ClipboardHistorySplit")
        splitView.autosaveName = "ClipboardHistorySplit"
        splitView.addArrangedSubview(listSide)
        splitView.addArrangedSubview(historyPreviewView)

        contentView.addSubview(searchField)
        contentView.addSubview(splitView)

        window?.contentView = contentView

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            splitView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        // Default split: list ~380, preview takes the rest. The autosave
        // name above means the user's drag-position survives relaunches.
        DispatchQueue.main.async { [weak splitView] in
            splitView?.setPosition(380, ofDividerAt: 0)
        }
    }

    func observeClips() {
        guard let realm = realm else { return }
        clipToken = realm.objects(CPYClip.self).observe { [weak self] _ in
            guard let self = self else { return }
            if self.isWindowVisible {
                self.scheduleReload()
            } else {
                self.pendingReload = true
            }
        }
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.reloadEntries()
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    func observeDefaults() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.settings = MenuSettings()
            self.tableView.rowHeight = self.computedRowHeight()
            if self.isWindowVisible {
                self.tableView.reloadData()
            }
        }
    }

    /// Row height grows to fit the thumbnail when any image-style preview is
    /// enabled (Show Image / Show color preview / Show icon). When all of
    /// those are off, fall back to a tighter title-only row.
    private func computedRowHeight() -> CGFloat {
        let imagey = settings.isShowImage || settings.isShowColorCode || settings.isShowIcon
        guard imagey else { return 28 }
        return max(72, CGFloat(settings.thumbnailHeight) + 8)
    }

    func observeWorkspace() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication
            self?.rememberReturnApplication(application)
        }
    }

    func rememberReturnApplication(_ application: NSRunningApplication?) {
        guard let application = application else { return }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        returnApplication = application
    }

    func reloadEntries() {
        guard let realm = realm else { return }
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        // Pinned clips always sort to the top; within each group, the user's
        // existing order preference (newest first vs reorder-after-paste)
        // is preserved.
        let descriptors: [RealmSwift.SortDescriptor] = [
            RealmSwift.SortDescriptor(keyPath: #keyPath(CPYClip.isPinned), ascending: false),
            RealmSwift.SortDescriptor(keyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        ]
        entries = realm.objects(CPYClip.self)
            .sorted(by: descriptors)
            .map(ClipboardHistoryEntry.init)
        applyFilter(searchField.stringValue)
    }

    func applyFilter(_ query: String) {
        let selectedPrimaryKey = selectedEntry?.primaryKey
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.isEmpty {
            filteredEntries = entries
        } else {
            filteredEntries = entries.filter {
                $0.searchText.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }

        tableView.reloadData()
        updateEmptyState()
        restoreSelection(primaryKey: selectedPrimaryKey)
    }

    func updateEmptyState() {
        let isEmpty = filteredEntries.isEmpty
        scrollView.isHidden = isEmpty
        emptyStateLabel.isHidden = !isEmpty
    }

    func restoreSelection(primaryKey: String?) {
        guard !filteredEntries.isEmpty else {
            tableView.deselectAll(nil)
            return
        }

        if let primaryKey = primaryKey,
           let row = filteredEntries.firstIndex(where: { $0.primaryKey == primaryKey }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    var selectedEntry: ClipboardHistoryEntry? {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < filteredEntries.count else { return nil }
        return filteredEntries[selectedRow]
    }

    @objc func confirmSelection(_ sender: Any?) {
        guard let entry = selectedEntry ?? filteredEntries.first else {
            NSSound.beep()
            return
        }

        guard let realm = Realm.safeInstance() else { return }
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: entry.primaryKey) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: clip)

        close()
    }
}

// MARK: - NSWindowDelegate

extension CPYClipboardHistoryWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isWindowVisible = false
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        searchField.stringValue = ""
        returnApplication = nil
        entries.removeAll()
        filteredEntries.removeAll()
        tableView.reloadData()
    }
}

// MARK: - NSSearchFieldDelegate

extension CPYClipboardHistoryWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            confirmSelection(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !filteredEntries.isEmpty else { return true }
            let row = max(tableView.selectedRow, 0)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            window?.makeFirstResponder(tableView)
            return true
        default:
            return false
        }
    }
}

// MARK: - NSTableViewDataSource, NSTableViewDelegate

extension CPYClipboardHistoryWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredEntries[row]
        let cellView = (tableView.makeView(withIdentifier: ClipboardHistoryCellView.reuseIdentifier, owner: nil) as? ClipboardHistoryCellView)
            ?? ClipboardHistoryCellView(frame: .zero)
        cellView.configure(with: entry, settings: settings)
        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        historyPreviewView.show(entry: selectedEntry)
        // QLPreviewPanel re-asks the data source when the index changes.
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
        }
    }

    /// Drag-out: let the user pick up a row and drop it into any other app.
    /// Text-like clips drag as `NSString` (lands cleanly in text fields);
    /// file/image/PDF clips materialise to a temp file URL (the same one
    /// Quick Look uses), which Finder/other apps consume as a copyable file.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < filteredEntries.count else { return nil }
        let entry = filteredEntries[row]
        let type = NSPasteboard.PasteboardType(rawValue: entry.primaryType)

        switch type {
        case .deprecatedTIFF, .tiff, .png, .deprecatedPDF, .pdf,
             .deprecatedFilenames, .fileURL:
            if let url = quickLookURL(for: entry) {
                return url as NSURL
            }
            return nil
        default:
            if let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: entry.dataPath),
               !clipData.stringValue.isEmpty {
                return NSString(string: clipData.stringValue)
            }
            // Last resort: drag the visible title rather than nothing.
            return entry.displayTitle.isEmpty ? nil : NSString(string: entry.displayTitle)
        }
    }
}

// MARK: - NSSplitViewDelegate

extension CPYClipboardHistoryWindowController: NSSplitViewDelegate {
    // Keep both panes usable: the list won't shrink past one cell width and
    // the preview won't disappear entirely.
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        return 280
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        return splitView.bounds.width - 240
    }
}

// MARK: - Open In Default App

extension CPYClipboardHistoryWindowController {
    /// Whether a clip with this pasteboard type can be opened in an external
    /// app. Pure (no instance state), so the spec exercises it directly.
    static func isOpenablePrimaryType(_ rawType: String) -> Bool {
        let type = NSPasteboard.PasteboardType(rawValue: rawType)
        switch type {
        case .deprecatedTIFF, .tiff, .png, .deprecatedPDF, .pdf,
             .deprecatedFilenames, .fileURL:
            return true
        default:
            return false
        }
    }

    /// Open a clip's payload in the default app by primary key. Shared by the
    /// history window's right-click + Cmd+O surfaces and the menu-bar popup
    /// menu's right-click monitor (`MenuManager.installPopupRightClickMonitor`).
    static func openClipInDefaultApp(primaryKey: String) {
        guard let realm = Realm.safeInstance(),
              let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }
        openClipInDefaultApp(rawType: clip.primaryType, dataPath: clip.dataPath, primaryKey: primaryKey)
    }

    static func openClipInDefaultApp(rawType: String, dataPath: String, primaryKey: String) {
        let type = NSPasteboard.PasteboardType(rawValue: rawType)

        if type == .deprecatedFilenames || type == .fileURL {
            if let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: dataPath),
               let path = clipData.fileNames.first {
                openURL(URL(fileURLWithPath: path))
                return
            }
            NSSound.beep()
            return
        }

        guard let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: dataPath) else {
            NSLog("CPYClipboardHistoryWindow: failed to unarchive clip at \(dataPath)")
            NSSound.beep()
            return
        }

        if type == .deprecatedTIFF || type == .tiff || type == .png {
            guard let image = clipData.image,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]),
                  let url = writeToTempFile(data: png, ext: "png") else {
                NSLog("CPYClipboardHistoryWindow: failed to materialise PNG for clip \(primaryKey)")
                NSSound.beep()
                return
            }
            openURL(url)
            return
        }

        if type == .deprecatedPDF || type == .pdf {
            guard let data = clipData.PDF, let url = writeToTempFile(data: data, ext: "pdf") else {
                NSLog("CPYClipboardHistoryWindow: failed to materialise PDF for clip \(primaryKey)")
                NSSound.beep()
                return
            }
            openURL(url)
            return
        }

        NSLog("CPYClipboardHistoryWindow: nothing to open for type \(rawType)")
        NSSound.beep()
    }

    static func writeToTempFile(data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipy-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

private extension CPYClipboardHistoryWindowController {
    func makeContextMenu(forRow row: Int) -> NSMenu? {
        guard row >= 0, row < filteredEntries.count else { return nil }
        let entry = filteredEntries[row]
        let menu = NSMenu()

        // Pin / Unpin is always available — pinned clips survive trimming
        // and float to the top of the list.
        let pinTitle = entry.isPinned ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle,
                                 action: #selector(togglePinContextMenuAction(_:)),
                                 keyEquivalent: "")
        pinItem.target = self
        pinItem.representedObject = entry.primaryKey
        menu.addItem(pinItem)

        // Open-in-default-app only makes sense for openable types.
        if isOpenableEntry(entry) {
            menu.addItem(NSMenuItem.separator())
            let openItem = NSMenuItem(title: "Open in Default App",
                                      action: #selector(openContextMenuAction(_:)),
                                      keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = entry.primaryKey
            menu.addItem(openItem)
        }

        menu.addItem(NSMenuItem.separator())
        let deleteItem = NSMenuItem(title: "Delete",
                                    action: #selector(deleteContextMenuAction(_:)),
                                    keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = entry.primaryKey
        menu.addItem(deleteItem)

        return menu
    }

    @objc func deleteContextMenuAction(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String,
              let realm = Realm.safeInstance(),
              let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey) else { return }
        AppEnvironment.current.clipService.delete(with: clip)
    }

    @objc func openContextMenuAction(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String,
              let entry = filteredEntries.first(where: { $0.primaryKey == primaryKey }) else { return }
        openEntryInDefaultApp(entry)
    }

    @objc func togglePinContextMenuAction(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String else { return }
        guard let realm = Realm.safeInstance(),
              let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey) else { return }
        realm.transaction { clip.isPinned.toggle() }
        // Realm notification → scheduleReload picks the new state up,
        // resort + redraw happens automatically.
    }

    func openSelectedInDefaultApp() {
        guard let entry = selectedEntry else {
            NSSound.beep()
            return
        }
        openEntryInDefaultApp(entry)
    }

    /// Cmd+1..9/0 quick-paste: select the Nth visible row and reuse the
    /// existing confirmSelection flow so all the side effects (copy to
    /// pasteboard, close window) match a normal Enter/click. Beep on miss.
    func quickPaste(at index: Int) {
        guard index >= 0, index < filteredEntries.count else {
            NSSound.beep()
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        confirmSelection(nil)
    }

    func isOpenableEntry(_ entry: ClipboardHistoryEntry) -> Bool {
        return CPYClipboardHistoryWindowController.isOpenablePrimaryType(entry.primaryType)
    }

    func openEntryInDefaultApp(_ entry: ClipboardHistoryEntry) {
        Self.openClipInDefaultApp(rawType: entry.primaryType,
                                  dataPath: entry.dataPath,
                                  primaryKey: entry.primaryKey)
    }
}

private extension CPYClipboardHistoryWindowController {
    /// Open a URL through LaunchServices. Logs the underlying error if it
    /// fails (silent failures are otherwise indistinguishable from "user
    /// app refused to launch"). File-private; both static and instance
    /// open-paths funnel through here.
    static func openURL(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { app, error in
            if let error = error {
                NSLog("CPYClipboardHistoryWindow: NSWorkspace.open(\(url.path)) failed — \(error)")
            } else if app == nil {
                NSLog("CPYClipboardHistoryWindow: NSWorkspace.open(\(url.path)) returned nil app, no error")
            }
        }
    }
}

// MARK: - Quick Look

/// QLPreviewItem wrapper. We give Quick Look a single item per invocation
/// (the currently-selected row), materialised lazily as a temp file URL.
private final class HistoryQuickLookItem: NSObject, QLPreviewItem {
    let url: URL
    let title: String
    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
    var previewItemURL: URL? { url }
    var previewItemTitle: String? { title }
}

// QLPreviewPanelDataSource ships pre-Swift-6 isolation; the panel only
// ever calls these on main, so @preconcurrency suppresses the warning.
@MainActor extension CPYClipboardHistoryWindowController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {

    /// Toggle Quick Look for the selected row. Bound to Space in the table.
    /// Falls back to a beep when the entry can't be materialised — the user
    /// should still feel a response rather than silent inaction.
    func toggleQuickLook() {
        guard selectedEntry != nil else { NSSound.beep(); return }
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return selectedEntry == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let entry = selectedEntry,
              let url = quickLookURL(for: entry) else {
            return nil
        }
        return HistoryQuickLookItem(url: url, title: entry.displayTitle)
    }

    /// Materialise an entry for Quick Look. Files reuse their original
    /// path (lossless, no temp); image/PDF/text/url clips drop to a temp
    /// file alongside the existing open-in-default-app temp files.
    private func quickLookURL(for entry: ClipboardHistoryEntry) -> URL? {
        let type = NSPasteboard.PasteboardType(rawValue: entry.primaryType)

        if type == .deprecatedFilenames || type == .fileURL,
           let path = ClipboardHistoryCellView.firstFilePath(from: entry) {
            return URL(fileURLWithPath: path)
        }

        guard let clipData = LegacyKeyedArchive.unarchivedObject(of: CPYClipData.self, fromFile: entry.dataPath) else {
            return nil
        }

        if type == .deprecatedTIFF || type == .tiff || type == .png,
           let image = clipData.image,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return Self.writeToTempFile(data: png, ext: "png")
        }

        if type == .deprecatedPDF || type == .pdf, let data = clipData.PDF {
            return Self.writeToTempFile(data: data, ext: "pdf")
        }

        // Fallback: any clip with a string body — including URLs and
        // RTF-with-string-fallback — gets a quick `.txt` so QL renders a
        // readable preview without needing per-format converters.
        if !clipData.stringValue.isEmpty,
           let body = clipData.stringValue.data(using: .utf8) {
            return Self.writeToTempFile(data: body, ext: "txt")
        }

        return nil
    }
}

// HistoryPreviewView lives in `HistoryPreviewView.swift` to keep this file
// under the 500-line SwiftLint cap.
