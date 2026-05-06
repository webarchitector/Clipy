//
//  CPYInputSourcesPreferenceViewController.swift
//
//  Programmatic preferences pane: one row per available input source with
//  icon, localized name, and a KeyHolder RecordView for binding a hotkey.
//

import Cocoa
import KeyHolder
import Magnet

final class CPYInputSourcesPreferenceViewController: NSViewController {

    private var rows: [(source: InputSource, recordView: RecordView)] = []

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        for source in InputSource.sources {
            let row = makeRow(for: source)
            stack.addArrangedSubview(row)
        }

        // Stack must size to its content; scroll view's document view
        // ignores autoresizing the way we want unless we pin width.
        let stackContainer = NSView()
        stackContainer.translatesAutoresizingMaskIntoConstraints = false
        stackContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: stackContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: stackContainer.trailingAnchor),
            stack.topAnchor.constraint(equalTo: stackContainer.topAnchor),
            stack.bottomAnchor.constraint(equalTo: stackContainer.bottomAnchor)
        ])

        scroll.documentView = stackContainer
        scroll.contentView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stackContainer.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])

        view = root
    }

    private func makeRow(for source: InputSource) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = source.icon
        iconView.imageScaling = .scaleProportionallyDown

        let nameLabel = NSTextField(labelWithString: source.name)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let recordView = RecordView()
        recordView.translatesAutoresizingMaskIntoConstraints = false
        recordView.tintColor = NSColor(red: 0.165, green: 0.518, blue: 0.824, alpha: 1)
        recordView.cornerRadius = 17
        recordView.delegate = self
        recordView.keyCombo = AppEnvironment.current.inputSourceService.keyCombo(for: source)

        row.addSubview(iconView)
        row.addSubview(nameLabel)
        row.addSubview(recordView)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 34),
            row.widthAnchor.constraint(greaterThanOrEqualToConstant: 440),

            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: recordView.leadingAnchor, constant: -8),

            recordView.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            recordView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            recordView.widthAnchor.constraint(equalToConstant: 220),
            recordView.heightAnchor.constraint(equalToConstant: 34)
        ])

        rows.append((source, recordView))
        return row
    }
}

extension CPYInputSourcesPreferenceViewController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool { true }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool { true }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        guard let row = rows.first(where: { $0.recordView === recordView }) else { return }
        AppEnvironment.current.inputSourceService.change(source: row.source, keyCombo: keyCombo)

        // De-dup: clear any other RecordView that happens to display the
        // same KeyCombo (the service has just unregistered the old binding).
        if let combo = keyCombo {
            for (_, rv) in rows where rv !== recordView && rv.keyCombo == combo {
                rv.keyCombo = nil
            }
        }
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
