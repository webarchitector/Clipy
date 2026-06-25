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
    case scratchpad(noteCount: Int)
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

    let scratchpadStore = ScratchpadStore()
    private var launcherScroll: NSScrollView!
    private var inScratchpad = false
    private lazy var scratchpad = ScratchpadController(
        store: scratchpadStore,
        copyToPasteboard: { [weak self] s in self?.copyToPasteboard(s) },
        hidePanel: { [weak self] in self?.hide() },
        exitToRoot: { [weak self] in self?.exitScratchpad() }
    )

    var visibleItems: [LauncherItem] = []
    private var runningApps: Set<String> = []
    private var lastQuery: String = ""
    private var pendingFilterWorkItem: DispatchWorkItem?
    private var runningAppsObservers: [NSObjectProtocol] = []

    static let dotTag = 1001

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

        // Always reopen at the app-selection root, even if the panel was closed
        // while in scratchpad mode.
        if inScratchpad { exitScratchpad() }

        AppIndex.shared.reloadIfNeeded()
        ensureRunningAppsTracking()
        searchField.stringValue = ""
        lastQuery = ""
        pendingFilterWorkItem?.cancel()
        pendingFilterWorkItem = nil
        // applyFilter populates visibleItems and (since panel is off-screen)
        // resizes via setContentSize, so center() lands the already-fitted
        // panel in the middle of the screen.
        applyFilter("")
        panel.center()
        // Non-activating path: don't call NSApp.activate. WindowServer
        // denies SetFrontProcessWithInfo while another app holds Secure
        // Event Input (Safari htpasswd sheet, login fields, etc.), and
        // a denied activate leaves the panel invisible. orderFrontRegardless
        // + makeKey mirrors how Spotlight/Alfred/Raycast surface a search
        // field over modal sheets without stealing process focus.
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        if inScratchpad { exitScratchpad() }
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
            // .nonactivatingPanel lets the panel become key without
            // flipping the process to frontmost — required so the
            // launcher surfaces over Safari/login sheets that have
            // engaged Secure Event Input (WindowServer would otherwise
            // deny SetFrontProcessWithInfo and the panel never appears).
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Clipy Launcher"
        // .statusBar sits above modal sheets and full-screen windows so
        // the launcher is reachable from any context. .floating wasn't
        // high enough to overlay a foreground app's modal sheet.
        p.level = .statusBar
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
        self.launcherScroll = scroll
    }

    // MARK: - Scratchpad mode

    private func enterScratchpad() {
        guard let content = panel?.contentView, let sf = searchField else { return }
        inScratchpad = true
        // Scratchpad uses a large fixed window (wide + near-full height), so it
        // does not collapse to fit content like the app-launcher results do.
        scratchpad.onHeightChange = nil
        sizeForScratchpad()
        scratchpad.enter(contentView: content, searchField: sf, launcherScroll: launcherScroll)
    }

    private func exitScratchpad() {
        inScratchpad = false
        scratchpad.leave()
        searchField?.delegate = self
        searchField?.stringValue = ""
        applyFilter("")
        panel?.center()
    }

    private func sizeForScratchpad() {
        guard let panel = panel else { return }
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let width = min(900, visible.width - 80)
        let height = visible.height - 80
        let origin = NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)),
                       display: true, animate: false)
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
        let scratchCount = q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? scratchpadStore.allNotes().count : 0
        visibleItems = LauncherItems.withScratchpad(prefixing: items,
                                                    query: q,
                                                    noteCount: scratchCount)

        tableView?.reloadData()
        if !visibleItems.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        resizePanelToFit()
    }

    /// Shrinks the panel to fit `visibleItems`, anchoring the top edge so the
    /// window collapses upward as results narrow (Spotlight/Alfred behaviour).
    /// The first `show()` seeds a preferred height + centers; subsequent
    /// resizes preserve `frame.maxY`.
    private func resizePanelToFit() {
        guard let panel = panel else { return }
        let rowHeight: CGFloat = 24
        let rowSpacing: CGFloat = 2
        let topPad: CGFloat = 8
        let searchFieldHeight: CGFloat = 28
        let gapBelowSearch: CGFloat = 6
        let bottomPad: CGFloat = 8

        let n = visibleItems.count
        // Include trailing rowSpacing + small cushion so the scroll view's
        // container is comfortably larger than its document — otherwise the
        // overlay scroller can flicker in on a row-count boundary (e.g. the
        // 2-row `3+5=` result).
        let tableHeight = n > 0
            ? CGFloat(n) * (rowHeight + rowSpacing) + 4
            : 0
        let gap = n > 0 ? gapBelowSearch : 0
        let desiredContent = topPad + searchFieldHeight + gap + tableHeight + bottomPad

        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 600, height: 480)
        let oldFrame = panel.frame
        // Chrome = frame - content; computed from current frame so titled-bar
        // height stays accurate even if the system changes it under us.
        let currentContent = panel.contentRect(forFrameRect: oldFrame).size
        let chromeHeight = oldFrame.height - currentContent.height
        let maxFrameHeight = max(120, visible.height - 80)
        let maxContent = maxFrameHeight - chromeHeight
        let targetContent = max(searchFieldHeight + topPad + bottomPad,
                                min(desiredContent, maxContent))
        let targetFrameHeight = targetContent + chromeHeight
        if abs(oldFrame.height - targetFrameHeight) < 0.5 { return }

        // Off-screen (first show): adjust content; show()'s center() places it.
        // On-screen: preserve top edge so the panel collapses upward as
        // results narrow — matches Spotlight / Alfred / Raycast.
        if !panel.isVisible {
            panel.setContentSize(NSSize(width: oldFrame.width, height: targetContent))
            return
        }
        let topY = oldFrame.maxY
        let newOrigin = NSPoint(x: oldFrame.origin.x, y: topY - targetFrameHeight)
        panel.setFrame(NSRect(origin: newOrigin,
                              size: NSSize(width: oldFrame.width, height: targetFrameHeight)),
                       display: true, animate: false)
    }

}

// MARK: - NSSearchFieldDelegate

extension AppLauncher {
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
}

// MARK: - Activation

extension AppLauncher {
    func activateSelection() {
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
        case .scratchpad:
            enterScratchpad()
        }
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

// MARK: - NSWindowDelegate

extension AppLauncher {
    func windowWillClose(_ notification: Notification) {
        Calculator.shared.cancelPendingFetch()
    }
}
