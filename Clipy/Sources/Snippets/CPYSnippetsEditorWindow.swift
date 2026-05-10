//
//  CPYSnippetsEditorWindow.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

/// Snippets editor window subclass. Sole purpose right now is to override
/// Cmd+Q so the keystroke closes this window (mirrors Cmd+W) instead of
/// being consumed by `NSApp.terminate(_:)` and quitting the whole app —
/// users dismissing the editor almost never want to quit Clipy.
final class CPYSnippetsEditorWindow: NSWindow {

    /// Pure helper: returns true iff the (chars, mods) pair represents a
    /// "close this editor window" command. Russian-PC layout maps physical
    /// 'Q' to Cyrillic 'й', so we match both. Extracted as a static func so
    /// it can be unit-tested without spinning up an NSWindow (whose
    /// `close()` is unsafe in headless test environments).
    static func shouldCloseForKeyEquivalent(chars: String?, mods: NSEvent.ModifierFlags) -> Bool {
        let modMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard mods.intersection(modMask) == .command else { return false }
        guard let lower = chars?.lowercased() else { return false }
        return lower == "q" || lower == "й"
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.shouldCloseForKeyEquivalent(chars: event.charactersIgnoringModifiers,
                                            mods: event.modifierFlags) {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
