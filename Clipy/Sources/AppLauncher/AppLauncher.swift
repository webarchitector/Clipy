//
//  AppLauncher.swift
//
//  Clipy AppLauncher — NSPanel + filter + dispatch.
//

// swiftlint:disable identifier_name

import Cocoa

enum LauncherItem {
    case app(name: String, running: Bool)
    case calcCopyResult(expression: String, result: String)
    case calcCopyFull(expression: String, result: String)
    case status(String)
}

// Driven entirely from the main thread (NSPanel UI). @unchecked Sendable
// is the cheapest valid Swift 6 mark — actor isolation would cascade
// through every NSWindowDelegate/NSSearchFieldDelegate/NSTableViewDataSource
// method we already serialize on main.
final class AppLauncher: NSObject, NSWindowDelegate, NSSearchFieldDelegate,
                         NSTableViewDataSource, NSTableViewDelegate, @unchecked Sendable {

    static let shared = AppLauncher()

    // MARK: - Storage

    private var panel: NSPanel?
    private var searchField: NSSearchField!
    private var tableView: NSTableView!

    private var visibleItems: [LauncherItem] = []
    private var runningApps: Set<String> = []
    private var lastQuery: String = ""
    private var pendingFilterWorkItem: DispatchWorkItem?
    private var runningAppsObservers: [NSObjectProtocol] = []

    private static let dotTag = 1001

    // MARK: - Hotkey entry points

    func toggle() {
        if let p = panel, p.isVisible {
            hide()
        } else {
            // Dismiss any other Clipy UI (history popup, history window,
            // snippet popup) so the launcher takes focus cleanly.
            AppEnvironment.current.menuManager.dismissAllPopups()
            show()
        }
    }

    /// Build the panel + warm caches off the critical path so the first
    /// hotkey press is as fast as every subsequent one. Called once from
    /// AppLauncherService.setupHotKey().
    func preload() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            if self.panel == nil { self.setupPanel() }
            AppIndex.shared.reloadIfNeeded()
            self.ensureRunningAppsTracking()
        }
    }

    func show() {
        if panel == nil { setupPanel() }
        guard let panel = panel, let searchField = searchField else { return }

        AppIndex.shared.reloadIfNeeded()
        ensureRunningAppsTracking()
        searchField.stringValue = ""
        lastQuery = ""
        pendingFilterWorkItem?.cancel()
        pendingFilterWorkItem = nil
        applyFilter("")

        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 600, height: 480)
        let preferredHeight: CGFloat = 760
        let maxHeight = max(240, visible.height - 80)
        let targetHeight = min(preferredHeight, maxHeight)
        panel.setContentSize(NSSize(width: 600, height: targetHeight))

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        panel?.orderOut(nil)
        pendingFilterWorkItem?.cancel()
        pendingFilterWorkItem = nil
        Calculator.shared.cancelPendingFetch()
    }

    /// Called from background workers (AppIndex async rebuild, Calculator
    /// currency fetch) when fresh data has just landed and the visible
    /// filter result needs to be redrawn.
    func rebuildDidFinish() {
        guard let panel = panel, panel.isVisible else { return }
        applyFilter(lastQuery)
    }

    private func refreshRunningApps() {
        var s: Set<String> = []
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular {
            if let name = app.localizedName { s.insert(name) }
        }
        runningApps = s
    }

    /// Replaces per-show `runningApplications` scans with NSWorkspace notifications.
    /// One initial scan seeds the set; afterwards launch/terminate events keep it
    /// fresh, so opening the launcher costs zero extra work for this purpose.
    private func ensureRunningAppsTracking() {
        if !runningAppsObservers.isEmpty { return }
        let nc = NSWorkspace.shared.notificationCenter
        let launch = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                    object: nil, queue: .main) { [weak self] _ in
            self?.refreshRunningApps()
        }
        let terminate = nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                       object: nil, queue: .main) { [weak self] _ in
            self?.refreshRunningApps()
        }
        runningAppsObservers = [launch, terminate]
        refreshRunningApps()
    }

    // MARK: - Panel setup

    private func setupPanel() {
        let p = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        p.title = "Clipy Launcher"
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self

        let content = NSView()

        let sf = NSSearchField()
        sf.delegate = self
        sf.placeholderString = "App, math (`(1+2)=`), or currency (`15 usd thb=`)"
        sf.font = NSFont.systemFont(ofSize: 16)
        if let cell = sf.cell as? NSTextFieldCell {
            cell.isScrollable = true
            cell.usesSingleLineMode = true
            cell.wraps = false
        }
        sf.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sf)

        let tv = NSTableView()
        tv.dataSource = self
        tv.delegate = self
        tv.headerView = nil
        tv.rowHeight = 24
        tv.selectionHighlightStyle = .regular
        tv.style = .plain
        tv.intercellSpacing = NSSize(width: 0, height: 2)
        tv.target = self
        tv.action = #selector(rowClicked)
        tv.doubleAction = #selector(rowClicked)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.width = 580
        tv.addTableColumn(col)

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            sf.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            sf.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            sf.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            sf.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: sf.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])

        p.contentView = content
        self.panel = p
        self.searchField = sf
        self.tableView = tv
    }

    // MARK: - Filter

    private func applyFilter(_ rawQuery: String) {
        let q = rawQuery.precomposedStringWithCanonicalMapping
        lastQuery = q

        var items: [LauncherItem] = []
        items.append(contentsOf: Calculator.shared.items(for: q))
        for (name, running) in AppIndex.shared.match(query: q, runningNames: runningApps) {
            items.append(.app(name: name, running: running))
        }
        visibleItems = items

        tableView?.reloadData()
        if !visibleItems.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { visibleItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: self)
                    as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("cell")

        let dotLabel: NSTextField = (cell.viewWithTag(Self.dotTag) as? NSTextField) ?? {
            let d = NSTextField(labelWithString: "●")
            d.tag = Self.dotTag
            d.font = NSFont.systemFont(ofSize: 14)
            d.textColor = NSColor.systemGreen
            d.alignment = .right
            d.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(d)
            NSLayoutConstraint.activate([
                d.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                d.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                d.widthAnchor.constraint(equalToConstant: 16)
            ])
            return d
        }()

        let tf = cell.textField ?? {
            let f = NSTextField(labelWithString: "")
            f.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(f)
            cell.textField = f
            NSLayoutConstraint.activate([
                f.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                f.trailingAnchor.constraint(equalTo: dotLabel.leadingAnchor, constant: -6),
                f.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return f
        }()
        tf.font = NSFont.systemFont(ofSize: 14)
        tf.lineBreakMode = .byTruncatingTail
        tf.textColor = NSColor.labelColor

        switch visibleItems[row] {
        case let .app(name, running):
            tf.stringValue = name
            dotLabel.isHidden = !running
        case let .calcCopyResult(expr, result):
            tf.stringValue = "🧮 \(expr) = \(result)   (Enter to copy result)"
            dotLabel.isHidden = true
        case let .calcCopyFull(expr, result):
            tf.stringValue = "📋 \(expr) = \(result)   (Enter to copy expression = result)"
            dotLabel.isHidden = true
        case let .status(msg):
            tf.stringValue = msg
            tf.textColor = .secondaryLabelColor
            dotLabel.isHidden = true
        }
        return cell
    }

    @objc private func rowClicked() {
        activateSelection()
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        // Coalesce keystrokes: O(n) match across ~500 apps + table reload + potential
        // currency fetch shouldn't run on every character. Flushed eagerly on Enter /
        // arrow-key navigation so the visible selection always matches the query.
        let query = searchField.stringValue
        pendingFilterWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingFilterWorkItem = nil
            self?.applyFilter(query)
        }
        pendingFilterWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60), execute: work)
    }

    private func flushPendingFilter() {
        guard let work = pendingFilterWorkItem else { return }
        work.cancel()
        pendingFilterWorkItem = nil
        applyFilter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            flushPendingFilter()
            activateSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            pendingFilterWorkItem?.cancel()
            pendingFilterWorkItem = nil
            hide()
            return true
        case #selector(NSResponder.moveDown(_:)):
            flushPendingFilter()
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            flushPendingFilter()
            moveSelection(by: -1)
            return true
        default:
            return false
        }
    }

    func moveSelection(by delta: Int) {
        guard !visibleItems.isEmpty else { return }
        let current = tableView.selectedRow
        var next = current + delta
        if next < 0 { next = 0 }
        if next >= visibleItems.count { next = visibleItems.count - 1 }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    // MARK: - Activation

    private func activateSelection() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard row < visibleItems.count else { hide(); return }
        let item = visibleItems[row]
        switch item {
        case .app(let name, _):
            hide()
            if let url = AppIndex.shared.resolveURL(named: name) {
                NSWorkspace.shared.openApplication(at: url,
                                                   configuration: NSWorkspace.OpenConfiguration(),
                                                   completionHandler: nil)
            }
        case let .calcCopyResult(_, result):
            copyToPasteboard(result)
            hide()
        case let .calcCopyFull(expr, result):
            copyToPasteboard("\(expr) = \(result)")
            hide()
        case .status:
            break
        }
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        Calculator.shared.cancelPendingFetch()
    }
}
