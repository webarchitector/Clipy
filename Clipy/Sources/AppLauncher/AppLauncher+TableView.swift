import Cocoa

// MARK: - NSTableView data source / delegate

extension AppLauncher {
    func numberOfRows(in tableView: NSTableView) -> Int { visibleItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: self)
                    as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("cell")

        let dotLabel: NSTextField = (cell.viewWithTag(Self.dotTag) as? NSTextField) ?? {
            let dot = NSTextField(labelWithString: "●")
            dot.tag = Self.dotTag
            dot.font = NSFont.systemFont(ofSize: 14)
            dot.textColor = NSColor.systemGreen
            dot.alignment = .right
            dot.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 16)
            ])
            return dot
        }()

        let label = cell.textField ?? {
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                field.trailingAnchor.constraint(equalTo: dotLabel.leadingAnchor, constant: -6),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return field
        }()
        label.font = NSFont.systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = NSColor.labelColor

        switch visibleItems[row] {
        case let .app(name, running):
            label.stringValue = name
            dotLabel.isHidden = !running
        case let .calcCopyResult(expr, result):
            label.stringValue = "🧮 \(expr) = \(result)   (Enter to copy result)"
            dotLabel.isHidden = true
        case let .calcCopyFull(expr, result):
            label.stringValue = "📋 \(expr) = \(result)   (Enter to copy expression = result)"
            dotLabel.isHidden = true
        case let .status(msg):
            label.stringValue = msg
            label.textColor = .secondaryLabelColor
            dotLabel.isHidden = true
        case let .scratchpad(noteCount):
            label.stringValue = "📝 Scratchpad (\(noteCount))"
            dotLabel.isHidden = true
        }
        return cell
    }

    @objc func rowClicked() {
        activateSelection()
    }
}
