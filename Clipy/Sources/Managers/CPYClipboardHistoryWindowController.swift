//
//  CPYClipboardHistoryWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//

import Cocoa
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

    init(clip: CPYClip) {
        primaryKey = clip.dataHash
        thumbnailPath = clip.thumbnailPath
        isColorCode = clip.isColorCode
        dataPath = clip.dataPath
        primaryType = clip.primaryType

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

// MARK: - Table View

final class ClipboardHistoryTableView: NSTableView {
    var confirmHandler: (() -> Void)?
    var cancelHandler: (() -> Void)?

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
        case 53:
            cancelHandler?()
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Window Controller

final class CPYClipboardHistoryWindowController: NSWindowController {
    static let sharedController = CPYClipboardHistoryWindowController()

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = ClipboardHistoryTableView()
    private let emptyStateLabel = NSTextField(labelWithString: L10n.noMatchingHistoryItems)
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
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered,
                             defer: false)
        super.init(window: window)
        configureWindow()
        configureContentView()
        observeWorkspace()
        observeClips()
        observeDefaults()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        clipToken?.invalidate()
        if let workspaceObserver = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let defaultsObserver = defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        rememberReturnApplication(NSWorkspace.shared.frontmostApplication)
        searchField.stringValue = ""
        isWindowVisible = true
        pendingReload = false
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        settings = MenuSettings()
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
        tableView.rowHeight = 72
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

        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyStateLabel)

        window?.contentView = contentView

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 16),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -16)
        ])
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
            if self.isWindowVisible {
                self.tableView.reloadData()
            }
        }
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
        entries = realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
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
}
