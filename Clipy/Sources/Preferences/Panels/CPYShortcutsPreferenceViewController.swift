//
//  CPYShortcutsPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/26.
//
//  Copyright © 2015-2018 Clipy Project.
//

// swiftlint:disable identifier_name

import Cocoa
// @preconcurrency: KeyHolder's RecordViewDelegate isn't annotated for
// Swift 6 strict concurrency, so its main-actor crossing surfaces as a
// data-race error in our conformance. The protocol callbacks already
// fire on main from KeyHolder's NSView subclass; the import opt-out
// suppresses the warning until KeyHolder ships @MainActor annotations.
@preconcurrency import KeyHolder
import Magnet

class CPYShortcutsPreferenceViewController: NSViewController {

    // MARK: - Properties
    @IBOutlet private weak var mainShortcutRecordView: RecordView!
    @IBOutlet private weak var historyShortcutRecordView: RecordView!
    @IBOutlet private weak var snippetShortcutRecordView: RecordView!
    @IBOutlet private weak var clearHistoryShortcutRecordView: RecordView!
    @IBOutlet private weak var appLauncherShortcutRecordView: RecordView!

    /// Programmatically appended rows for each available input source.
    /// Indexed by RecordView identity so the delegate can map back.
    private var inputSourceRows: [(source: InputSource, recordView: RecordView)] = []

    // MARK: - Initialize
    override func loadView() {
        super.loadView()
        mainShortcutRecordView.delegate = self
        historyShortcutRecordView.delegate = self
        snippetShortcutRecordView.delegate = self
        clearHistoryShortcutRecordView.delegate = self
        appLauncherShortcutRecordView?.delegate = self
        prepareHotKeys()
        appendInputSourcesSection()
    }

}

// MARK: - Shortcut
private extension CPYShortcutsPreferenceViewController {
    func prepareHotKeys() {
        mainShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.mainKeyCombo
        historyShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.historyKeyCombo
        snippetShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.snippetKeyCombo
        clearHistoryShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.clearHistoryKeyCombo
        appLauncherShortcutRecordView?.keyCombo = AppEnvironment.current.appLauncherService.currentKeyCombo
    }
}

// MARK: - Input Sources section
//
// The XIB carries the static rows (Menu / Clear History) at the top of the
// view. After it loads, we measure how many keyboard layouts the user has
// installed, grow the parent view to fit, and append:
//   - "Layouts" section header
//   - one row (icon + name + RecordView) per input source
// All XIB-loaded subviews carry `flexibleMinY` autoresizing — increasing
// `view.frame.size.height` makes them slide up so the new empty space
// appears at the bottom (low y), where we drop the new section.
private extension CPYShortcutsPreferenceViewController {

    static let layoutsHeaderHeight: CGFloat = 17
    static let layoutsRowHeight: CGFloat = 34
    static let layoutsRowGap: CGFloat = 12
    static let layoutsTopPadding: CGFloat = 24
    static let layoutsBottomPadding: CGFloat = 16
    static let layoutsHeaderToFirstRowGap: CGFloat = 12

    func appendInputSourcesSection() {
        let sources = InputSource.sources
        guard !sources.isEmpty else { return }

        let extraHeight =
            Self.layoutsTopPadding +
            Self.layoutsHeaderHeight +
            Self.layoutsHeaderToFirstRowGap +
            CGFloat(sources.count) * Self.layoutsRowHeight +
            CGFloat(max(sources.count - 1, 0)) * Self.layoutsRowGap +
            Self.layoutsBottomPadding

        // Cap visual height so a user with many layouts doesn't end up with a
        // window taller than the screen. ~5 rows fit before we start
        // truncating; beyond the cap the section becomes scrollable.
        let scrollableThreshold: CGFloat = 280
        let useScrollView = extraHeight > scrollableThreshold
        let actualExtraHeight = useScrollView ? scrollableThreshold : extraHeight

        var frame = view.frame
        frame.size.height += actualExtraHeight
        view.frame = frame

        // After the resize, existing XIB subviews have slid up; y range
        // [0, actualExtraHeight] is the new empty area at the bottom.
        let sectionTop = actualExtraHeight - Self.layoutsTopPadding

        // "Layouts" section header
        let header = NSTextField(labelWithString: "Layouts")
        header.frame = NSRect(
            x: 59,
            y: sectionTop - Self.layoutsHeaderHeight,
            width: 210,
            height: Self.layoutsHeaderHeight
        )
        header.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        header.textColor = NSColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1)
        header.autoresizingMask = [.maxXMargin, .minYMargin]
        view.addSubview(header)

        let firstRowTop = sectionTop - Self.layoutsHeaderHeight - Self.layoutsHeaderToFirstRowGap

        if useScrollView {
            let scroll = NSScrollView(frame: NSRect(
                x: 44,
                y: Self.layoutsBottomPadding,
                width: view.frame.width - 88,
                height: firstRowTop - Self.layoutsBottomPadding
            ))
            scroll.hasVerticalScroller = true
            scroll.borderType = .noBorder
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.autoresizingMask = [.width, .maxXMargin, .minYMargin]

            let totalContentHeight =
                CGFloat(sources.count) * Self.layoutsRowHeight +
                CGFloat(max(sources.count - 1, 0)) * Self.layoutsRowGap

            let document = NSView(frame: NSRect(
                x: 0, y: 0,
                width: scroll.contentSize.width,
                height: totalContentHeight
            ))
            document.autoresizingMask = [.width]

            for (index, source) in sources.enumerated() {
                // Inside scroll's flipped-coords document view, top-most row
                // sits at the highest y; index 0 is at the top.
                let rowY = totalContentHeight
                    - CGFloat(index + 1) * Self.layoutsRowHeight
                    - CGFloat(index) * Self.layoutsRowGap
                let row = makeInputSourceRow(source: source, atY: rowY, parentWidth: document.frame.width)
                document.addSubview(row)
            }

            scroll.documentView = document
            view.addSubview(scroll)
        } else {
            for (index, source) in sources.enumerated() {
                let rowY = firstRowTop
                    - CGFloat(index + 1) * Self.layoutsRowHeight
                    - CGFloat(index) * Self.layoutsRowGap
                let row = makeInputSourceRow(source: source, atY: rowY, parentWidth: view.frame.width)
                view.addSubview(row)
            }
        }
    }

    func makeInputSourceRow(source: InputSource, atY y: CGFloat, parentWidth: CGFloat) -> NSView {
        // Mirrors the XIB's static-row layout: label on the left, RecordView
        // on the right, vertically centred in a 34pt-tall row.
        let row = NSView(frame: NSRect(x: 0, y: y, width: parentWidth, height: Self.layoutsRowHeight))
        row.autoresizingMask = [.width]

        let icon = NSImageView(frame: NSRect(x: 44, y: 7, width: 20, height: 20))
        icon.image = source.icon
        icon.imageScaling = .scaleProportionallyDown
        icon.autoresizingMask = [.maxXMargin]
        row.addSubview(icon)

        let labelX: CGFloat = 70
        let recordWidth: CGFloat = 250
        let recordX = parentWidth - 44 - recordWidth
        let labelWidth = max(recordX - labelX - 8, 80)

        let label = NSTextField(labelWithString: source.name)
        label.frame = NSRect(x: labelX, y: 8, width: labelWidth, height: 17)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = NSColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1)
        label.autoresizingMask = [.width, .maxXMargin]
        row.addSubview(label)

        let recordView = RecordView(frame: NSRect(x: recordX, y: 0, width: recordWidth, height: 34))
        recordView.tintColor = NSColor(red: 0.165, green: 0.518, blue: 0.824, alpha: 1)
        recordView.cornerRadius = 17
        recordView.delegate = self
        recordView.keyCombo = AppEnvironment.current.inputSourceService.keyCombo(for: source)
        recordView.autoresizingMask = [.minXMargin]
        row.addSubview(recordView)

        inputSourceRows.append((source, recordView))
        return row
    }
}

// MARK: - RecordView Delegate
// Conformance is unsafe-bridged because RecordViewDelegate isn't yet
// marked @MainActor in KeyHolder; the callbacks fire from KeyHolder's
// own main-thread NSView.
@MainActor extension CPYShortcutsPreferenceViewController: @preconcurrency RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        return true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        return true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        switch recordView {
        case mainShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .main, keyCombo: keyCombo)
        case historyShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .history, keyCombo: keyCombo)
        case snippetShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .snippet, keyCombo: keyCombo)
        case clearHistoryShortcutRecordView:
            AppEnvironment.current.hotKeyService.changeClearHistoryKeyCombo(keyCombo)
        case appLauncherShortcutRecordView:
            AppEnvironment.current.appLauncherService.change(keyCombo: keyCombo)
        default:
            // Maybe this is one of the appended input source rows.
            if let row = inputSourceRows.first(where: { $0.recordView === recordView }) {
                AppEnvironment.current.inputSourceService.change(source: row.source, keyCombo: keyCombo)
                // De-dup: if another row showed the same combo, the service
                // unregistered it; clear the visual to match.
                if let combo = keyCombo {
                    for (_, rv) in inputSourceRows where rv !== recordView && rv.keyCombo == combo {
                        rv.keyCombo = nil
                    }
                }
            }
        }
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
