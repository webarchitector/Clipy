//
//  SnippetEditorSelectionGuard.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

/// Pure helper that decides whether a textView write should be allowed.
/// Lives here so the editor's "is the user editing the snippet they think
/// they're editing?" defense can be unit-tested without instantiating
/// the controller.
enum SnippetEditorSelectionGuard {
    /// `true` only when both IDs are non-nil and identical. A nil on either
    /// side (or a mismatch) means the textView is showing content for a
    /// different snippet than the outline view currently has selected; the
    /// caller should reject the write and re-sync the UI.
    static func writeIsSafe(displayedID: String?, selectedID: String?) -> Bool {
        guard let displayedID = displayedID, let selectedID = selectedID else { return false }
        return displayedID == selectedID
    }
}
