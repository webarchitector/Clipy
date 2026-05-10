# Snippet Search in the Editor — Design

**Date:** 2026-05-10
**Author:** brainstorming session

## Goal

Add a search field to the snippets editor (`CPYSnippetsEditorWindowController`) that filters the outline view in real time. Matches are found by case- and diacritic-insensitive substring against snippet titles and snippet content. Folder titles do not match, but ancestor folders of matching snippets stay visible so the tree path is preserved.

## Out of scope

- Search in folder titles (decision Q1).
- Highlighting matched substrings within the displayed text (no rich text in cells today).
- Search-result-only export, drag-out to other apps, or other operations beyond what the editor already supports.
- Server-side / fuzzy / regex search.

## Constraints decided in brainstorming

| # | Decision |
|---|----------|
| 1 | Search scope = snippet `title` + snippet `content`. Folder titles excluded. |
| 2 | Display = filtered tree. Ancestors of matched snippets stay visible and auto-expanded. Empty query → full tree restored. |
| 3 | UI = `NSSearchField` placed above the outline view inside the left split pane. ⌘F focuses the field via responder-chain `findInSnippets:`. Esc clears query, then Esc again returns focus to the outline view. |
| 4 | Reactivity = real-time on every keystroke (no debounce). |
| 5 | Expanded-state preservation = snapshot expanded folder IDs on first entry into search mode; restore on clear. |
| 6 | Drag-drop stays enabled while filtered; `NestedMoveExecutor` learns about hidden siblings via a new optional `visibleIDs` parameter. |

## Filter helper (pure)

New file `Clipy/Sources/Snippets/SnippetSearchFilter.swift`:

```swift
import Foundation
import RealmSwift

enum SnippetSearchFilter {
    /// Returns the set of node identifiers (snippets + ancestor folders)
    /// that should remain visible when the editor outline is filtered by
    /// `query`. Empty / whitespace-only query returns nil (= no filter
    /// active). Matching rule: locale-aware case- and diacritic-insensitive
    /// substring against snippet `title` or `content`. Folder titles are
    /// not matched directly; folders appear in the result only as
    /// ancestors of matched snippets.
    static func visibleIdentifiers(query: String, in realm: Realm) -> Set<String>? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Realm CONTAINS[cd] = case- and diacritic-insensitive substring.
        let matches = realm.objects(CPYSnippet.self)
            .filter("title CONTAINS[cd] %@ OR content CONTAINS[cd] %@", trimmed, trimmed)
        var result = Set<String>()
        for snippet in matches {
            result.insert(snippet.identifier)
            var pid = snippet.parentIdentifier
            while !pid.isEmpty, !result.contains(pid) {
                result.insert(pid)
                guard let parent = realm.object(ofType: CPYFolder.self, forPrimaryKey: pid) else { break }
                pid = parent.parentIdentifier
            }
        }
        return result
    }
}
```

The ancestor walk dedupes via `result.contains` so a snippet whose chain already visited stays linear.

## Editor controller integration

New stored properties on `CPYSnippetsEditorWindowController`:

```swift
@IBOutlet private weak var searchField: NSSearchField!

/// Currently active filter set (nil = no filter). When non-nil, every
/// node id in the set is visible; everything else is hidden.
private var visibleIdentifiers: Set<String>?

/// Snapshot of folder IDs that were expanded when the user first entered
/// search mode. Used to restore the tree after clearing the query.
private var savedExpandedIDs: Set<String>?
```

### Children query, filtered

`children(parentId:)` extends the existing cache to honour `visibleIdentifiers`:

```swift
func children(parentId: String) -> [Object] {
    if let cached = childrenCache[parentId] { return cached }
    guard let realm = Realm.safeInstance() else { return [] }
    var kids = CPYFolder.children(parentIdentifier: parentId, in: realm)
    if let visible = visibleIdentifiers {
        kids = kids.filter { visible.contains(idOf($0)) }
    }
    childrenCache[parentId] = kids
    return kids
}

private static func idOf(_ obj: Object) -> String {
    if let folder = obj as? CPYFolder { return folder.identifier }
    if let snippet = obj as? CPYSnippet { return snippet.identifier }
    return ""
}
```

The cache is invalidated by `reloadOutline()` (already exists) and additionally by `applyFilter` before reload.

### `applyFilter(_ query: String)`

```swift
private func applyFilter(_ query: String) {
    guard let realm = Realm.safeInstance() else { return }
    let new = SnippetSearchFilter.visibleIdentifiers(query: query, in: realm)
    let wasNil = (visibleIdentifiers == nil)
    let willBeNil = (new == nil)
    let previouslySelectedID = selectedItemIdentifier()

    if wasNil && !willBeNil {
        savedExpandedIDs = collectExpandedFolderIDs()
    }
    visibleIdentifiers = new
    reloadOutline()

    if !willBeNil {
        // Auto-expand every visible folder so ancestors of matches are walkable.
        expandAllVisibleFolders()
    } else if let saved = savedExpandedIDs {
        // Restore previous expansion.
        outlineView.collapseItem(nil, collapseChildren: true)
        for id in saved {
            if let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: id) {
                outlineView.expandItem(folder)
            }
        }
        savedExpandedIDs = nil
    }

    restoreSelection(previouslySelectedID: previouslySelectedID)
}
```

### Helpers

```swift
private func selectedItemIdentifier() -> String? {
    guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
    if let folder = item as? CPYFolder { return folder.identifier }
    if let snippet = item as? CPYSnippet { return snippet.identifier }
    return nil
}

private func collectExpandedFolderIDs() -> Set<String> {
    var ids = Set<String>()
    for row in 0..<outlineView.numberOfRows {
        let item = outlineView.item(atRow: row) as Any
        if let folder = item as? CPYFolder, outlineView.isItemExpanded(folder) {
            ids.insert(folder.identifier)
        }
    }
    return ids
}

private func expandAllVisibleFolders() {
    guard let visible = visibleIdentifiers else { return }
    guard let realm = Realm.safeInstance() else { return }
    for id in visible {
        if let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: id) {
            outlineView.expandItem(folder)
        }
    }
}

private func restoreSelection(previouslySelectedID: String?) {
    guard let realm = Realm.safeInstance() else { return }
    if let id = previouslySelectedID {
        let item: Any? = (realm.object(ofType: CPYFolder.self, forPrimaryKey: id) as Any?)
            ?? (realm.object(ofType: CPYSnippet.self, forPrimaryKey: id) as Any?)
        if let item = item, isCurrentlyVisible(item) {
            let row = outlineView.row(forItem: item)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                changeItemFocus()
                return
            }
        }
    }
    // Fall back to first visible row if any, else clear.
    if outlineView.numberOfRows > 0 {
        outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        changeItemFocus()
    } else {
        outlineView.deselectAll(nil)
        changeItemFocus()
    }
}

private func isCurrentlyVisible(_ item: Any) -> Bool {
    if visibleIdentifiers == nil { return true }
    return outlineView.row(forItem: item) >= 0
}
```

### Search field wiring

In `windowDidLoad`:

```swift
searchField.placeholderString = L10n.searchSnippets
searchField.target = self
searchField.action = #selector(searchFieldChanged(_:))
searchField.delegate = self
```

```swift
@objc private func searchFieldChanged(_ sender: NSSearchField) {
    applyFilter(sender.stringValue)
}

// Responder-chain target for the new menu item Edit → Find (⌘F).
@IBAction func findInSnippets(_ sender: Any?) {
    window?.makeFirstResponder(searchField)
}
```

### `NSSearchFieldDelegate`

```swift
extension CPYSnippetsEditorWindowController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if !searchField.stringValue.isEmpty {
                searchField.stringValue = ""
                applyFilter("")
            } else {
                window?.makeFirstResponder(outlineView)
            }
            return true
        }
        return false
    }
}
```

`NSSearchField` already fires its `action` on every keystroke, so `applyFilter` runs in real time without an extra `controlTextDidChange` hook.

## XIB changes

`Clipy/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib`:

- Inside the left pane of `CPYSplitView`, wrap the existing `NSScrollView` (containing the outline view) in a vertical `NSView` container.
- Add an `NSSearchField` at the top of that container:
  - leading + trailing pinned to the container with constant 8.
  - top pinned to the container top with constant 8.
  - height 22 (default).
- Repin the existing `NSScrollView`:
  - top pinned to `searchField.bottom` with constant 6.
  - leading / trailing / bottom unchanged.
- Hook the search field to a new outlet on the file owner: `searchField` (NSSearchField).

The right pane (folder settings + text view) is unchanged.

## Menu bar item for ⌘F

Edit `Clipy/Xibs/MainMenu.xib` (the project's only main menu) and add an `Edit → Find` menu item:

- Title: `L10n.find` (existing localization if present; otherwise add `find = "Find"`).
- Key equivalent: `⌘F`.
- Action: `findInSnippets:` (selector with no concrete target — routes through the responder chain).

The action only fires when the snippets editor window is key (responder chain hits the controller). When the clipboard history window is key, ⌘F still routes to its own search field (already wired in that controller).

If the project does not yet have an `Edit → Find` group, add the menu item under whichever menu currently hosts editor commands. The exact xib edit is part of the implementation plan; spec-level guarantee is "a menu item with title=Find, key=⌘F, action=`findInSnippets:`".

## Drag-and-drop with active filter

`NestedMoveExecutor.move` gains an optional parameter:

```swift
static func move(itemId: String,
                 isFolder: Bool,
                 toParentId: String,
                 atIndex: Int,
                 visibleIDs: Set<String>? = nil,
                 in realm: Realm) {
```

When `visibleIDs == nil`, the existing behaviour is preserved exactly (no filter — all sibling indices reflect the full set).

When `visibleIDs != nil`:

1. `let allKids = CPYFolder.children(parentIdentifier: toParentId, in: realm)` (full set, includes moved item, since `parentIdentifier` was already updated above).
2. Partition `allKids` into `visibleKids = allKids.filter { visibleIDs.contains(idOf($0)) }` and a parallel record `hiddenAnchors: [(item, prevVisibleID?)]` where `prevVisibleID` is the identifier of the closest visible sibling that came before each hidden item in the original `allKids` order (nil if there was none — meaning that hidden item is supposed to go before all visibles).
3. Build the new visible order: `var newVisible = visibleKids.filter { idOf($0) != itemId }`. Insert the moved item at `clamp(atIndex, 0, newVisible.count)`.
4. Reconstruct the full order: walk `newVisible`. Maintain a `lastVisibleID` cursor. Before placing each visible item, drain every hidden item whose `prevVisibleID` equals the cursor (in their original order). After placing, set `lastVisibleID = idOf(item)`. After the loop, drain hidden items whose `prevVisibleID == lastVisibleID` (i.e. trailing hidden tail). Hidden items whose anchor was nil go at the very front, before the first visible.
5. Renumber the resulting full order 0..n-1 as today.

Caller in `acceptDrop` passes the controller's `visibleIdentifiers` through. When the filter is inactive the parameter defaults to nil and the old code path runs.

### Edge cases

- Drop onto a folder (no specific position, `atIndex == -1`): treated as append to the end of `newVisible`. Because hidden trailing tail is then re-appended after, the moved item ends up at "end of visible, before any trailing hidden" — which matches the user's visual intent.
- Drag a snippet into a folder whose entire visible content is the moved item (i.e., the only filtered match was that snippet): `newVisible` becomes `[movedItem]`, hidden siblings restored around it. Renumber gives consistent indices.
- Drag a folder while filter is active: cycle / depth checks in `DropValidator` already operate on the full realm (not on `visibleIDs`), so they remain correct. The `visibleIDs`-aware reordering only affects the renumber step, not validation.

## Tests

### `SnippetSearchFilterSpec` (new)

- Empty query → nil.
- Whitespace-only query (`"   "`) → nil.
- Match by title returns the snippet ID and chain of ancestor folder IDs.
- Match by content returns the snippet ID and ancestors.
- Case-insensitive: query `"Hello"` matches snippet titled `"hello world"`.
- Diacritic-insensitive: query `"jose"` matches snippet titled `"José"`.
- No matches → empty `Set` (not nil — distinguishes "filter active, nothing matched" from "filter inactive").
- Deeply nested (5 levels): every ancestor folder up to root is in the set.

### `NestedDragDropSpec` (extend)

- Existing tests still pass (visibleIDs default = nil).
- New test: parent has siblings `[A_visible, B_hidden, C_visible, D_hidden]` (indices 0..3). Move A_visible to `atIndex=1` in filtered view (visible = `[A, C]`). Final full order should be `[B, C, A, D]` (B keeps its anchor "before all visibles"; D keeps its anchor "after C", which moves with C; A is now at the visible-position-1 = after C). Indices renumbered 0..3.
- Symmetric test: move C_visible to `atIndex=0` in filtered view → expected full order `[B, C, A, D]`. (Same final state — moves are symmetric in a 2-visible list.)

### `CPYSnippetsEditorWindowControllerSpec` (optional, may skip if AppKit dep is heavy)

The controller-level tests are hard because they touch outline view + xib. Skip; coverage of `applyFilter` flow comes from the pure helper + drag-drop spec, plus manual smoke.

## Manual smoke

After the implementation:

1. Open the snippets editor with a tree containing a few folders and snippets, including a nested 3-level branch.
2. Click into the search field, type a fragment of a snippet title — see the tree filter to that snippet, with ancestor folders auto-expanded.
3. Clear the field — tree returns to its previous expanded state, selection preserved if visible.
4. Type a fragment of snippet content — same filtering, snippet matched on body text.
5. Press ⌘F from anywhere in the editor window — search field gains focus.
6. Press Esc with text in the field — text clears, focus stays in field. Press Esc again — focus moves to outline view.
7. With filter active, drag a visible snippet between two visible siblings; clear the filter; verify hidden siblings are still in their relative positions.

## Files affected

| File | Change |
|------|--------|
| `Clipy/Sources/Snippets/SnippetSearchFilter.swift` (new) | Pure filter helper. |
| `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift` | Add `searchField` outlet, `visibleIdentifiers` / `savedExpandedIDs`, filter integration in `children(parentId:)`, `applyFilter`, helpers, search-field action + delegate, `findInSnippets:` action. |
| `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift` | `acceptDrop` passes `visibleIdentifiers` to `NestedMoveExecutor.move`. |
| `Clipy/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib` | Insert `NSSearchField` above outline view; outlet wiring. |
| `Clipy/Xibs/MainMenu.xib` | Add `Edit → Find` menu item with action `findInSnippets:` and key equivalent ⌘F. |
| `Clipy/Resources/en.lproj/Localizable.strings` (and the other `<lang>.lproj/Localizable.strings`) (and other .lproj) | Add `searchSnippets = "Search snippets"` (localized in each .strings). SwiftGen regenerates `L10n.searchSnippets`. |
| `Clipy.xcodeproj/project.pbxproj` | Register new source files. |
| `ClipyTests/SnippetSearchFilterSpec.swift` (new) | Filter unit tests. |
| `ClipyTests/NestedDragDropSpec.swift` | Add filtered-move tests. |
| `Clipy.xcodeproj/project.pbxproj` | Register new test files. |

## Risks

- **Realm `CONTAINS[cd]` performance** on very large snippet collections. Negligible for typical usage (dozens to a few hundred snippets); if it ever bites, switch to in-memory `localizedCaseInsensitiveContains` over a pre-built searchText cache (the same trick `CPYClipboardHistoryWindowController` uses for clips).
- **Auto-expand cost**: `expandAllVisibleFolders` calls `outlineView.expandItem` for every folder in `visibleIdentifiers`. For a deep tree with many matches that's still tens of calls — fine.
- **Hidden-sibling drag-drop** has nontrivial reordering logic. Covered by tests; if a corner case slips, the worst outcome is a renumber that places the moved item one slot off — easy to inspect by clearing the filter.

## Non-goals

- No persisted search query across sessions (cleared each time the editor opens).
- No recent-search history.
- No "search in selected folder only" scope.
- No keyboard navigation of matches (↓/↑, F3) beyond the standard outline view selection that already works.
