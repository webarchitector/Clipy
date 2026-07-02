import Cocoa

final class CPYSnippetPreferenceViewController: NSViewController {

    // MARK: - Properties
    private let sourcePopUp = NSPopUpButton()
    private let folderPopUp = NSPopUpButton()
    private let reloadFoldersButton: NSButton = {
        let btn = NSButton()
        btn.title = "Reload folders"
        btn.bezelStyle = .rounded
        return btn
    }()
    private let editInNotesButton: NSButton = {
        let btn = NSButton()
        btn.title = "Edit in Apple Notes"
        btn.bezelStyle = .rounded
        return btn
    }()
    private let refreshButton: NSButton = {
        let btn = NSButton()
        btn.title = "Refresh snippets"
        btn.bezelStyle = .rounded
        return btn
    }()
    private let statusLabel: NSTextField = {
        let field = NSTextField()
        field.isEditable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isSelectable = true
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 4
        field.preferredMaxLayoutWidth = 440
        return field
    }()

    // MARK: - View Lifecycle

    override func loadView() {
        // "Snippet source" row
        sourcePopUp.addItem(withTitle: "Native")
        sourcePopUp.item(withTitle: "Native")?.tag = 0
        sourcePopUp.addItem(withTitle: "Apple Notes")
        sourcePopUp.item(withTitle: "Apple Notes")?.tag = 1
        sourcePopUp.target = self
        sourcePopUp.action = #selector(sourceChanged(_:))

        // "Notes folder" row
        folderPopUp.target = self
        folderPopUp.action = #selector(folderSelected(_:))

        // Button row actions
        reloadFoldersButton.target = self
        reloadFoldersButton.action = #selector(reloadFoldersTapped(_:))
        editInNotesButton.target = self
        editInNotesButton.action = #selector(editInNotesTapped(_:))
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped(_:))

        // Rows
        let sourceRow = makeRow(labelText: "Snippet source:", control: sourcePopUp)
        let folderRow = makeRow(labelText: "Notes folder:", control: folderPopUp)

        let buttonRow = NSStackView(views: [reloadFoldersButton, editInNotesButton, refreshButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        // Outer vertical stack
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sourceRow)
        stack.addArrangedSubview(folderRow)
        stack.addArrangedSubview(buttonRow)
        stack.addArrangedSubview(statusLabel)

        let container = NSView()
        container.frame = NSRect(x: 0, y: 0, width: 480, height: 210)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20)
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourcePopUp.selectItem(withTag: SnippetSourceStore.current.rawValue)
        reloadFolders()
        updateEnabledState()
    }

    // MARK: - Helpers

    private func makeRow(labelText: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: labelText)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    // MARK: - Actions

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        let source = SnippetSource(rawValue: sender.selectedTag()) ?? .native
        SnippetSourceStore.current = source
        updateEnabledState()
        if source == .appleNotes { refreshTapped(refreshButton) }
        AppEnvironment.current.menuManager.rebuildSnippetSource()
    }

    @objc private func folderSelected(_ sender: NSPopUpButton) {
        SnippetSourceStore.appleNotesFolder = sender.titleOfSelectedItem
        refreshTapped(refreshButton)
    }

    @objc private func reloadFoldersTapped(_ sender: NSButton) {
        reloadFolders()
    }

    @objc private func editInNotesTapped(_ sender: NSButton) {
        DispatchQueue.global(qos: .userInitiated).async {
            AppEnvironment.current.appleNotesService.revealSelectedFolder()
        }
    }

    @objc private func refreshTapped(_ sender: NSButton) {
        statusLabel.stringValue = "Refreshing…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = AppEnvironment.current.appleNotesService.refresh()
            DispatchQueue.main.async {
                self?.applyRefreshResult(result)
                AppEnvironment.current.menuManager.rebuildSnippetSource()
            }
        }
    }

    private func reloadFolders() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = AppEnvironment.current.appleNotesService.availableFolders()
            DispatchQueue.main.async {
                switch result {
                case .success(let folders):
                    self?.folderPopUp.removeAllItems()
                    self?.folderPopUp.addItems(withTitles: folders)
                    if let selected = SnippetSourceStore.appleNotesFolder,
                       folders.contains(selected) {
                        self?.folderPopUp.selectItem(withTitle: selected)
                    } else {
                        SnippetSourceStore.appleNotesFolder = self?.folderPopUp.titleOfSelectedItem
                    }
                case .failure(let error):
                    self?.statusLabel.stringValue = self?.describe(error) ?? ""
                }
            }
        }
    }

    private func applyRefreshResult(_ result: Result<AppleNotesSummary, AppleNotesError>) {
        switch result {
        case .success(let summary):
            statusLabel.stringValue = "\(summary.folderCount) folders, \(summary.snippetCount) snippets"
        case .failure(let error):
            statusLabel.stringValue = describe(error)
        }
    }

    private func describe(_ error: AppleNotesError) -> String {
        switch error {
        case .notAuthorized:
            return "Not authorized. Grant Clipy access to Notes in System Settings → Privacy → Automation."
        case .notesUnavailable:
            return "Apple Notes is unavailable."
        case .folderNotFound:
            return "Selected Notes folder not found."
        case .scriptFailed(let message):
            return message
        }
    }

    private func updateEnabledState() {
        let isNotes = SnippetSourceStore.current == .appleNotes
        [folderPopUp, reloadFoldersButton, editInNotesButton, refreshButton].forEach { $0.isEnabled = isNotes }
    }
}
