//
//  LauncherPanel.swift
//
//  Clipy AppLauncher — NSPanel subclass for first-responder + key forwarding.
//

// swiftlint:disable identifier_name

import Cocoa

/// NSPanel subclass that:
/// - becomes key (so the search field can have focus)
/// - forwards standard editing key-equivalents to the first responder
///   (LSUIElement apps don't ship a visible Edit menu, so ⌘C/V/X/A/Z
///   wouldn't fire for an NSSearchField inside our panel without this)
/// - closes on Esc
/// - on ⌘, hides itself and opens Clipy preferences
final class LauncherPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        AppLauncher.shared.hide()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let mods = event.modifierFlags.intersection(mask)
        if mods == .command, let chars = event.charactersIgnoringModifiers {
            if chars == "," {
                AppLauncher.shared.hide()
                CPYPreferencesWindowController.sharedController.showWindow(self)
                return true
            }
            let selector: Selector? = {
                switch chars {
                case "c": return #selector(NSText.copy(_:))
                case "v": return #selector(NSText.paste(_:))
                case "x": return #selector(NSText.cut(_:))
                case "a": return #selector(NSStandardKeyBindingResponding.selectAll(_:))
                case "z": return Selector(("undo:"))
                default:  return nil
                }
            }()
            if let sel = selector,
               let fr = firstResponder,
               fr.tryToPerform(sel, with: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
