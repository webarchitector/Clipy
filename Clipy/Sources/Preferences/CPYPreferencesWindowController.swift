//
//  CPYPreferencesWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/25.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

final class CPYPreferencesWindowController: NSWindowController {

    // MARK: - Properties
    static let sharedController = CPYPreferencesWindowController(windowNibName: "CPYPreferencesWindowController")
    @IBOutlet private weak var toolBar: NSView!
    // ImageViews
    @IBOutlet private weak var generalImageView: NSImageView!
    @IBOutlet private weak var menuImageView: NSImageView!
    @IBOutlet private weak var typeImageView: NSImageView!
    @IBOutlet private weak var excludeImageView: NSImageView!
    @IBOutlet private weak var shortcutsImageView: NSImageView!
    @IBOutlet private weak var updatesImageView: NSImageView!
    @IBOutlet private weak var betaImageView: NSImageView!
    // Labels
    @IBOutlet private weak var generalTextField: NSTextField!
    @IBOutlet private weak var menuTextField: NSTextField!
    @IBOutlet private weak var typeTextField: NSTextField!
    @IBOutlet private weak var excludeTextField: NSTextField!
    @IBOutlet private weak var shortcutsTextField: NSTextField!
    @IBOutlet private weak var updatesTextField: NSTextField!
    @IBOutlet private weak var betaTextField: NSTextField!
    // Buttons
    @IBOutlet private weak var generalButton: NSButton!
    @IBOutlet private weak var menuButton: NSButton!
    @IBOutlet private weak var typeButton: NSButton!
    @IBOutlet private weak var excludeButton: NSButton!
    @IBOutlet private weak var shortcutsButton: NSButton!
    @IBOutlet private weak var updatesButton: NSButton!
    @IBOutlet private weak var betaButton: NSButton!
    // ViewController
    private let viewController: [NSViewController] = [
        NSViewController(nibName: "CPYGeneralPreferenceViewController", bundle: nil),
        NSViewController(nibName: "CPYMenuPreferenceViewController", bundle: nil),
        CPYTypePreferenceViewController(nibName: "CPYTypePreferenceViewController", bundle: nil),
        CPYExcludeAppPreferenceViewController(nibName: "CPYExcludeAppPreferenceViewController", bundle: nil),
        CPYShortcutsPreferenceViewController(nibName: "CPYShortcutsPreferenceViewController", bundle: nil),
        CPYUpdatesPreferenceViewController(nibName: "CPYUpdatesPreferenceViewController", bundle: nil),
        CPYBetaPreferenceViewController(nibName: "CPYBetaPreferenceViewController", bundle: nil),
        CPYSnippetPreferenceViewController()
    ]
    // Programmatic Snippets tab chrome (tag 7)
    private var snippetButton = NSButton()
    private var snippetImageView = NSImageView()
    private var snippetTextField = NSTextField()

    // MARK: - Window Life Cycle
    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.collectionBehavior = .canJoinAllSpaces
        self.window?.backgroundColor = .windowBackgroundColor
        self.window?.titlebarAppearsTransparent = true
        CPYUtilities.applyAdaptiveAppearance(to: toolBar)
        toolBarItemTapped(generalButton)
        generalButton.sendAction(on: .leftMouseDown)
        menuButton.sendAction(on: .leftMouseDown)
        typeButton.sendAction(on: .leftMouseDown)
        excludeButton.sendAction(on: .leftMouseDown)
        shortcutsButton.sendAction(on: .leftMouseDown)
        updatesButton.sendAction(on: .leftMouseDown)
        betaButton.sendAction(on: .leftMouseDown)
        installSnippetTab()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.backgroundColor = .windowBackgroundColor
        CPYUtilities.presentPreferencesWindow(window)
    }
}

// MARK: - IBActions
extension CPYPreferencesWindowController {
    @IBAction private func toolBarItemTapped(_ sender: NSButton) {
        selectedTab(sender.tag)
        switchView(sender.tag)
    }
}

// MARK: - NSWindow Delegate
extension CPYPreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let viewController = viewController[2] as? CPYTypePreferenceViewController {
            AppEnvironment.current.defaults.set(viewController.storeTypes, forKey: Constants.UserDefaults.storeTypes)
        }
        if let window = window, !window.makeFirstResponder(window) {
            window.endEditing(for: nil)
        }
        CPYUtilities.closePreferencesWindow()
    }
}

// MARK: - Layout
private extension CPYPreferencesWindowController {
    func installSnippetTab() {
        // Force layout so betaButton's container frame is valid
        toolBar.layoutSubtreeIfNeeded()

        // Derive position and size from the Beta tab's container view
        guard let betaContainer = betaButton.superview else { return }
        let tabWidth  = betaContainer.frame.width
        let tabHeight = betaContainer.frame.height
        let nextX     = betaContainer.frame.maxX

        let tabContainer = NSView(frame: NSRect(x: nextX, y: 0, width: tabWidth, height: tabHeight))

        // Image (mirrors XIB: x=7, y=24, w=36, h=24 in a 56-tall container)
        snippetImageView = NSImageView(frame: NSRect(x: 7, y: 24, width: 36, height: 24))
        snippetImageView.image = Asset.prefMenu.image
        snippetImageView.imageScaling = .scaleProportionallyDown
        tabContainer.addSubview(snippetImageView)

        // Label
        snippetTextField = NSTextField(frame: NSRect(x: 1, y: 8, width: tabWidth - 2, height: 12))
        snippetTextField.stringValue = "Snippets"
        snippetTextField.alignment = .center
        snippetTextField.isBezeled = false
        snippetTextField.isEditable = false
        snippetTextField.drawsBackground = false
        snippetTextField.font = NSFont.systemFont(ofSize: 9)
        snippetTextField.textColor = .secondaryLabelColor
        tabContainer.addSubview(snippetTextField)

        // Transparent click-through button (mirrors XIB bezelStyle / transparent)
        snippetButton = NSButton(frame: NSRect(x: 0, y: 0, width: tabWidth, height: tabHeight))
        snippetButton.tag = 7
        snippetButton.target = self
        snippetButton.action = #selector(toolBarItemTapped(_:))
        snippetButton.sendAction(on: .leftMouseDown)
        snippetButton.bezelStyle = .shadowlessSquare
        (snippetButton.cell as? NSButtonCell)?.isTransparent = true
        tabContainer.addSubview(snippetButton)

        toolBar.addSubview(tabContainer)
    }

    func resetImages() {
        generalImageView.image = Asset.prefGeneral.image
        menuImageView.image = Asset.prefMenu.image
        typeImageView.image = Asset.prefType.image
        excludeImageView.image = Asset.prefExcluded.image
        shortcutsImageView.image = Asset.prefShortcut.image
        updatesImageView.image = Asset.prefUpdate.image
        betaImageView.image = Asset.prefBeta.image

        generalTextField.textColor = .secondaryLabelColor
        menuTextField.textColor = .secondaryLabelColor
        typeTextField.textColor = .secondaryLabelColor
        excludeTextField.textColor = .secondaryLabelColor
        shortcutsTextField.textColor = .secondaryLabelColor
        updatesTextField.textColor = .secondaryLabelColor
        betaTextField.textColor = .secondaryLabelColor
        snippetTextField.textColor = .secondaryLabelColor
        snippetImageView.image = Asset.prefMenu.image
    }

    func selectedTab(_ index: Int) {
        resetImages()

        switch index {
        case 0:
            generalImageView.image = Asset.prefGeneralOn.image
            generalTextField.textColor = .controlAccentColor
        case 1:
            menuImageView.image = Asset.prefMenuOn.image
            menuTextField.textColor = .controlAccentColor
        case 2:
            typeImageView.image = Asset.prefTypeOn.image
            typeTextField.textColor = .controlAccentColor
        case 3:
            excludeImageView.image = Asset.prefExcludedOn.image
            excludeTextField.textColor = .controlAccentColor
        case 4:
            shortcutsImageView.image = Asset.prefShortcutOn.image
            shortcutsTextField.textColor = .controlAccentColor
        case 5:
            updatesImageView.image = Asset.prefUpdateOn.image
            updatesTextField.textColor = .controlAccentColor
        case 6:
            betaImageView.image = Asset.prefBetaOn.image
            betaTextField.textColor = .controlAccentColor
        case 7:
            snippetImageView.image = Asset.prefMenuOn.image
            snippetTextField.textColor = .controlAccentColor
        default: break
        }
    }

    func switchView(_ index: Int) {
        let newView = viewController[index].view
        // Remove current views without toolbar
        window?.contentView?.subviews.forEach { view in
            if view != toolBar {
                view.removeFromSuperview()
            }
        }
        // Resize view
        guard let window = window else { return }
        let frame = window.frame
        var newFrame = window.frameRect(forContentRect: newView.frame)
        newFrame.origin = frame.origin
        newFrame.origin.y += frame.height - newFrame.height - toolBar.frame.height
        newFrame.size.height += toolBar.frame.height
        window.setFrame(newFrame, display: true)
        window.contentView?.addSubview(newView)
        CPYUtilities.applyAdaptiveAppearance(to: newView)
    }
}
