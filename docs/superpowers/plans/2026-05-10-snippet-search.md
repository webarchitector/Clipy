# Snippet Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real-time search field to the snippets editor that filters the outline view by snippet title + content (case- and diacritic-insensitive substring), preserving the tree path of every match.

**Architecture:** Pure filter helper (`SnippetSearchFilter`) returns the set of visible node identifiers for a query. The editor controller stores `visibleIdentifiers` and an expanded-state snapshot, integrates the filter via the existing `children(parentId:)` cache, auto-expands ancestors of matches, and restores both expansion and selection on clear. ⌘F focuses the search field via responder chain (`findInSnippets:`). Drag-drop stays enabled while filtered; `NestedMoveExecutor.move` learns about hidden siblings via a new optional `visibleIDs` parameter and reorders accordingly.

**Tech Stack:** Swift 6 (strict concurrency), Cocoa, RealmSwift, Quick + Nimble, AppKit (`NSSearchField`, `NSOutlineView`). Build: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`. Test: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test`. Project file edits in `Clipy.xcodeproj/project.pbxproj` use the `AB05xxxxxxxxxxxxxxxxXXXX` UUID style for new files.

**Spec:** `docs/superpowers/specs/2026-05-10-snippet-search-design.md` (read first).

**Pre-reads (project conventions):**
- `CLAUDE.md` (build rules, commit-message style, no AI attribution)
- `AGENTS.md` (Swift 6 / Sendable conventions, editor invariants)
- Spec file above

---

## File map

**Created:**
- `Clipy/Sources/Snippets/SnippetSearchFilter.swift` — pure filter helper.
- `ClipyTests/SnippetSearchFilterSpec.swift` — Quick spec for the filter.

**Modified:**
- `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift` — add `searchField` outlet, `visibleIdentifiers` and `savedExpandedIDs` state, filter-aware `children(parentId:)`, `applyFilter`, helpers, search-field action, `findInSnippets:` IBAction, `NSSearchFieldDelegate` conformance.
- `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift` — `acceptDrop` passes `visibleIdentifiers` to `NestedMoveExecutor.move`. Add `visibleIDs:` optional parameter to `NestedMoveExecutor.move` (filter-aware reorder).
- `Clipy/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib` — insert `NSSearchField` above outline view in the left split pane; add outlet binding.
- `Clipy/Xibs/MainMenu.xib` — add `Edit → Find` menu item with action `findInSnippets:` and key equivalent ⌘F.
- `Clipy/Resources/en.lproj/Localizable.strings` (and other `<lang>.lproj/Localizable.strings`) — add `"Search Snippets" = "Search Snippets";` and `"Find" = "Find";`.
- `Clipy.xcodeproj/project.pbxproj` — register `SnippetSearchFilter.swift` and `SnippetSearchFilterSpec.swift`.
- `ClipyTests/NestedDragDropSpec.swift` — add filtered-move tests.

---

## Conventions for every task

- Build before commit: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build` (NEVER `clean build`).
- Test before commit: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test` (or scoped via `-only-testing:ClipyTests/<SpecName>`).
- Commit messages: short imperative English, no `feat:`/`fix:` prefix, no AI attribution. (See `CLAUDE.md`.)
- One logical change per commit.

---

### Task 1: Pure `SnippetSearchFilter` helper + spec

**Files:**
- Create: `Clipy/Sources/Snippets/SnippetSearchFilter.swift`
- Create: `ClipyTests/SnippetSearchFilterSpec.swift`
- Modify: `Clipy.xcodeproj/project.pbxproj` (register both files)

- [ ] **Step 1: Write the failing spec**

Create `ClipyTests/SnippetSearchFilterSpec.swift` with:

```swift
import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class SnippetSearchFilterSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        afterEach {
            let realm = try! Realm()
            try? realm.write { realm.deleteAll() }
        }

        describe("visibleIdentifiers") {

            it("returns nil for an empty query") {
                let realm = try! Realm()
                expect(SnippetSearchFilter.visibleIdentifiers(query: "", in: realm)).to(beNil())
            }

            it("returns nil for a whitespace-only query") {
                let realm = try! Realm()
                expect(SnippetSearchFilter.visibleIdentifiers(query: "   \t\n", in: realm)).to(beNil())
            }

            it("returns an empty set when there are no matches") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.title = "F"; folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "alpha"; snippet.content = "beta"
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "zzz", in: realm)
                expect(result).toNot(beNil())
                expect(result?.isEmpty) == true
            }

            it("matches snippet title (case-insensitive)") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "Hello World"; snippet.content = ""
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "hello", in: realm)
                expect(result?.contains(snippet.identifier)) == true
                expect(result?.contains(folder.identifier)) == true
            }

            it("matches snippet content") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "untitled"; snippet.content = "secret payload"
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "payload", in: realm)
                expect(result?.contains(snippet.identifier)) == true
                expect(result?.contains(folder.identifier)) == true
            }

            it("is diacritic-insensitive") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "José"; snippet.content = ""
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "jose", in: realm)
                expect(result?.contains(snippet.identifier)) == true
            }

            it("does NOT match folder titles") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.title = "Greetings"; folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "x"; snippet.content = "y"
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "Greetings", in: realm)
                expect(result?.isEmpty) == true
            }

            it("includes the full ancestor chain for a deeply nested match") {
                let realm = try! Realm()
                var prevID = ""
                var folderIDs: [String] = []
                for level in 0..<5 {
                    let folder = CPYFolder(); folder.title = "L\(level + 1)"; folder.index = 0
                    folder.parentIdentifier = prevID
                    try! realm.write { realm.add(folder) }
                    folderIDs.append(folder.identifier)
                    prevID = folder.identifier
                }
                let snippet = CPYSnippet(); snippet.title = "needle"; snippet.content = ""
                snippet.parentIdentifier = prevID; snippet.index = 0
                try! realm.write { realm.add(snippet) }

                let result = SnippetSearchFilter.visibleIdentifiers(query: "needle", in: realm)
                expect(result?.contains(snippet.identifier)) == true
                for fid in folderIDs {
                    expect(result?.contains(fid)) == true
                }
            }
        }
    }
}
```

- [ ] **Step 2: Register the spec in `Clipy.xcodeproj/project.pbxproj`**

Use UUIDs `AB05000000000000000E0001` (file ref) and `AB05000000000000000E0002` (build ref). Make four insertions.

(a) PBXBuildFile section — insert after the existing `AB05000000000000000D0002 /* SnippetXml.swift in Sources */` line (around line 16):

```
		AB05000000000000000E0002 /* SnippetSearchFilterSpec.swift in Sources */ = {isa = PBXBuildFile; fileRef = AB05000000000000000E0001 /* SnippetSearchFilterSpec.swift */; };
```

(b) PBXFileReference section — insert after the `AB05000000000000000D0001 /* SnippetXml.swift */` line:

```
		AB05000000000000000E0001 /* SnippetSearchFilterSpec.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = SnippetSearchFilterSpec.swift; sourceTree = "<group>"; };
```

(c) PBXGroup `ClipyTests` (the same group containing `AB05000000000000000C0001 /* SnippetXmlRoundTripSpec.swift */`) — add:

```
				AB05000000000000000E0001 /* SnippetSearchFilterSpec.swift */,
```

(d) PBXSourcesBuildPhase for the test target (the same one containing `AB05000000000000000C0002 /* SnippetXmlRoundTripSpec.swift in Sources */`) — add:

```
				AB05000000000000000E0002 /* SnippetSearchFilterSpec.swift in Sources */,
```

- [ ] **Step 3: Build to confirm tests fail to compile**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: FAIL — `Cannot find 'SnippetSearchFilter' in scope` (in the new spec file).

- [ ] **Step 4: Implement `SnippetSearchFilter`**

Create `Clipy/Sources/Snippets/SnippetSearchFilter.swift`:

```swift
//
//  SnippetSearchFilter.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import RealmSwift

/// Computes the set of node identifiers (snippets + ancestor folders) that
/// should remain visible when the snippets editor outline is filtered by a
/// search query. Empty / whitespace-only query returns nil (no filter
/// active). Matching rule: locale-aware case- and diacritic-insensitive
/// substring against snippet `title` or `content`. Folder titles are not
/// matched directly; folders appear in the result only as ancestors of
/// matched snippets.
enum SnippetSearchFilter {
    static func visibleIdentifiers(query: String, in realm: Realm) -> Set<String>? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
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

- [ ] **Step 5: Register `SnippetSearchFilter.swift` in `Clipy.xcodeproj/project.pbxproj`**

Use UUIDs `AB05000000000000000F0001` (file ref) and `AB05000000000000000F0002` (build ref).

(a) PBXBuildFile section — insert after the spec entry from Step 2(a):

```
		AB05000000000000000F0002 /* SnippetSearchFilter.swift in Sources */ = {isa = PBXBuildFile; fileRef = AB05000000000000000F0001 /* SnippetSearchFilter.swift */; };
```

(b) PBXFileReference section — insert after the spec entry from Step 2(b):

```
		AB05000000000000000F0001 /* SnippetSearchFilter.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = SnippetSearchFilter.swift; sourceTree = "<group>"; };
```

(c) PBXGroup `Snippets` (the same group containing `AB05000000000000000D0001 /* SnippetXml.swift */`) — add:

```
				AB05000000000000000F0001 /* SnippetSearchFilter.swift */,
```

(d) Main Clipy target's PBXSourcesBuildPhase (the same one containing `AB05000000000000000D0002 /* SnippetXml.swift in Sources */`) — add:

```
				AB05000000000000000F0002 /* SnippetSearchFilter.swift in Sources */,
```

- [ ] **Step 6: Build and run tests**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/SnippetSearchFilterSpec`
Expected: 7 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Clipy/Sources/Snippets/SnippetSearchFilter.swift \
        ClipyTests/SnippetSearchFilterSpec.swift \
        Clipy.xcodeproj/project.pbxproj
git commit -m "add SnippetSearchFilter helper for snippet editor search"
```

---

### Task 2: Wire search field into the editor (XIB + controller)

This task adds the search field, makes the editor's existing `children(parentId:)` cache filter-aware, implements `applyFilter` with expanded-state snapshot/restore and selection preservation, and wires the search field action + Esc handling. Drag-drop is left untouched in this task (Task 4 makes it filter-aware).

**Files:**
- Modify: `Clipy/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib`
- Modify: `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift`
- Modify: `Clipy/Resources/en.lproj/Localizable.strings` (and other `<lang>.lproj/Localizable.strings`)

- [ ] **Step 1: Add the `searchField` outlet declaration to the controller**

In `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift`, just under the existing `@IBOutlet private weak var outlineView: NSOutlineView!` block, add:

```swift
    @IBOutlet private weak var searchField: NSSearchField!

    /// Currently active filter set (nil = no filter). When non-nil, every
    /// node id in the set is visible; everything else is hidden.
    private var visibleIdentifiers: Set<String>?

    /// Snapshot of folder IDs that were expanded when the user first entered
    /// search mode. Used to restore the tree after clearing the query.
    private var savedExpandedIDs: Set<String>?
```

- [ ] **Step 2: Filter-aware `children(parentId:)` and id helper**

Replace the existing `children(parentId:)` body in `CPYSnippetsEditorWindowController.swift` with:

```swift
    func children(parentId: String) -> [Object] {
        if let cached = childrenCache[parentId] { return cached }
        guard let realm = Realm.safeInstance() else { return [] }
        var kids = CPYFolder.children(parentIdentifier: parentId, in: realm)
        if let visible = visibleIdentifiers {
            kids = kids.filter { visible.contains(Self.idOf($0)) }
        }
        childrenCache[parentId] = kids
        return kids
    }

    static func idOf(_ obj: Object) -> String {
        if let folder = obj as? CPYFolder { return folder.identifier }
        if let snippet = obj as? CPYSnippet { return snippet.identifier }
        return ""
    }
```

(The `idOf` helper is `static` and `internal` so `NestedMoveExecutor` and tests can use it without spinning up a controller.)

- [ ] **Step 3: Add `applyFilter` and supporting helpers**

Append the following methods to the same `CPYSnippetsEditorWindowController` class body (after `reloadOutline()`):

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
            expandAllVisibleFolders()
        } else if let saved = savedExpandedIDs {
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
            if let item = item {
                let row = outlineView.row(forItem: item)
                if row >= 0 {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                    changeItemFocus()
                    return
                }
            }
        }
        if outlineView.numberOfRows > 0 {
            outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            changeItemFocus()
        } else {
            outlineView.deselectAll(nil)
            changeItemFocus()
        }
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        applyFilter(sender.stringValue)
    }

    @IBAction func findInSnippets(_ sender: Any?) {
        window?.makeFirstResponder(searchField)
    }
```

- [ ] **Step 4: Wire search field action + delegate in `windowDidLoad`**

In `windowDidLoad`, just after `CPYUtilities.applyAdaptiveAppearance(to: window?.contentView)` (and before `reloadOutline()`), add:

```swift
        searchField.placeholderString = L10n.searchSnippets
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.delegate = self
```

- [ ] **Step 5: Conform to `NSSearchFieldDelegate` for Esc handling**

Append a new extension at the bottom of `CPYSnippetsEditorWindowController.swift`:

```swift
// MARK: - NSSearchFieldDelegate
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

`NSSearchFieldDelegate` inherits from `NSTextFieldDelegate` which inherits from `NSControlTextEditingDelegate`, where `control(_:textView:doCommandBy:)` is declared. The extension does not need any other delegate method.

- [ ] **Step 6: Add the L10n strings**

For each of these files, append the listed lines (exact strings — SwiftGen uses the key text to derive the Swift identifier):

`Clipy/Resources/en.lproj/Localizable.strings`:
```
"Search Snippets" = "Search Snippets";
"Find" = "Find";
```

`Clipy/Resources/de.lproj/Localizable.strings`:
```
"Search Snippets" = "Search Snippets";
"Find" = "Find";
```

`Clipy/Resources/it.lproj/Localizable.strings`:
```
"Search Snippets" = "Search Snippets";
"Find" = "Find";
```

`Clipy/Resources/zh-Hans.lproj/Localizable.strings`:
```
"Search Snippets" = "Search Snippets";
"Find" = "Find";
```

`Clipy/Resources/ja.lproj/Localizable.strings`:
```
"Search Snippets" = "スニペットを検索";
"Find" = "検索";
```

(Other locales use English as a placeholder — same pattern as the existing strings file. SwiftGen runs as a build-phase script and regenerates `Clipy/Generated/LocalizedStrings.swift` automatically; the new identifiers `L10n.searchSnippets` and `L10n.find` will appear after the next build.)

- [ ] **Step 7: Add the search field to the editor XIB**

Open `Clipy/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib` in Xcode (Interface Builder). Make these changes:

1. In the **left** split-view pane (the `customView` with id `gSL-Od-RtU`, which currently contains only the outline view's `scrollView` id `2KR-By-5Os`):
   - Drag an `NSSearchField` from the Object Library into the customView.
   - Pin it: leading and trailing to the customView's leading/trailing with constant 8, top to the customView's top with constant 8, height = 22 (default for `NSSearchField` — leave the height free unless Xcode complains).
2. Modify the existing `scrollView` (`2KR-By-5Os`) constraint:
   - Change its `top` constraint so it pins to the search field's `bottom` (constant 6), instead of pinning to the customView's top.
   - Leading / trailing / bottom constraints are unchanged.
3. Connect the new search field to the controller:
   - Right-click File's Owner → drag the `searchField` outlet to the new `NSSearchField`.
   - Right-click the search field → drag its `delegate` outlet to File's Owner.

If editing the XIB by hand instead of Xcode, the diff is more involved — recommend using Xcode UI for this step. After saving in Xcode, verify with `git diff -- Clipy/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib` that:
- A new `<searchField>` element is added inside `customView id="gSL-Od-RtU"`.
- A new `<outlet property="searchField" .../>` connection is added under the File's Owner connections (`<connections>` block at file top, currently containing the `outlineView` and `splitView` outlets).
- The `2KR-By-5Os` scrollView's top constraint references the new search field instead of the parent customView.

- [ ] **Step 8: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds. (SwiftGen regenerates `L10n.searchSnippets` and `L10n.find` during the build script.)

- [ ] **Step 9: Manual smoke**

Build Release per `CLAUDE.md`:

```bash
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  CONFIGURATION_BUILD_DIR=/Volumes/dev/code-dev/clipy/build/Release build
```

Quit running Clipy, then `open /Volumes/dev/code-dev/clipy/build/Release/Clipy.app`. Open the snippets editor (menubar → "Edit Snippets…"). Verify:

- Search field is visible above the outline view in the left pane.
- Typing a fragment of a snippet title or content filters the tree in real time; ancestors are auto-expanded.
- Clearing the field returns the tree to its previous expanded state.
- Esc with text in the field clears it (focus stays in field). Esc again returns focus to the outline view.

(⌘F is wired in Task 3.)

- [ ] **Step 10: Commit**

```bash
git add Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift \
        Clipy/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib \
        Clipy/Resources/en.lproj/Localizable.strings \
        Clipy/Resources/de.lproj/Localizable.strings \
        Clipy/Resources/it.lproj/Localizable.strings \
        Clipy/Resources/zh-Hans.lproj/Localizable.strings \
        Clipy/Resources/ja.lproj/Localizable.strings \
        Clipy/Generated/LocalizedStrings.swift
git commit -m "add real-time search field to snippets editor"
```

(`Clipy/Generated/LocalizedStrings.swift` is checked in and regenerated by SwiftGen each build — include it in the commit so the diff matches the strings change.)

---

### Task 3: ⌘F menu item routed via responder chain

**Files:**
- Modify: `Clipy/Xibs/MainMenu.xib`

- [ ] **Step 1: Add the Find menu item to MainMenu.xib**

Open `Clipy/Xibs/MainMenu.xib` in Xcode. In the existing `Edit` menu (look for the menu item with title `Edit`, id `JcI-Dh-fGJ`, submenu id `0NM-JT-t2d`):

1. Add a separator at the bottom of the existing `Edit` submenu items (after `Select All`).
2. Add a new `NSMenuItem`:
   - Title: `Find` (the `L10n.find` value will not be applied — menus loaded from xib use literal titles unless code overrides them; "Find" is fine in the menu bar).
   - Key equivalent: `f`, modifier: command.
   - Connection: drag the `selector` connection to First Responder (id `-1`) and pick `findInSnippets:`. (After this xib edit, the connection xml will look like `<action selector="findInSnippets:" target="-1" id="<new-id>"/>`.)

If editing by hand: insert these lines just before the closing `</items>` of the Edit submenu (line ~135 area in the current xib):

```xml
                            <menuItem isSeparatorItem="YES" id="AB05000000000000000F1001">
                                <modifierMask key="keyEquivalentModifierMask" command="YES"/>
                            </menuItem>
                            <menuItem title="Find" keyEquivalent="f" id="AB05000000000000000F1002">
                                <connections>
                                    <action selector="findInSnippets:" target="-1" id="AB05000000000000000F1003"/>
                                </connections>
                            </menuItem>
```

(IDs `AB05000000000000000F1001..1003` are arbitrary 24-char hex strings unique within the xib.)

- [ ] **Step 2: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

- [ ] **Step 3: Manual smoke**

Rebuild Release as in Task 2 Step 9. Open the snippets editor. Press ⌘F — search field gains focus. Press ⌘F again — focus stays in the search field (no toggling, no error).

If the snippets editor is not key (e.g., the clipboard history search window is frontmost), ⌘F has no effect on the snippets editor (responder chain delivers it elsewhere or no-ops). This is the desired behaviour because the clipboard history window has its own independent search field.

- [ ] **Step 4: Commit**

```bash
git add Clipy/Xibs/MainMenu.xib
git commit -m "add edit find menu item routed via responder chain"
```

---

### Task 4: Filter-aware drag-and-drop

**Files:**
- Modify: `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift`
- Modify: `ClipyTests/NestedDragDropSpec.swift`

- [ ] **Step 1: Write failing tests**

Append the following describe block at the end of `NestedDragDropSpec.spec()` (just before the final closing `}` of the class):

```swift
        describe("Move execution with active filter") {

            it("places the moved item at the visible-position-N slot, preserving hidden anchors") {
                // Parent has 4 siblings A B C D (indices 0..3). Visible = {A, C}.
                // Move A to atIndex=1 in the visible view -> visible becomes [C, A].
                // Hidden siblings stay glued to their preceding visible neighbour:
                //   B's preceding visible is A -> B follows A.
                //   D's preceding visible is C -> D follows C (C did not move).
                // Final full order: [C, D, A, B].
                let realm = try! Realm()
                let parent = CPYFolder(); parent.index = 0
                try! realm.write { realm.add(parent) }
                let folderA = CPYFolder(); folderA.title = "A"; folderA.parentIdentifier = parent.identifier; folderA.index = 0
                let folderB = CPYFolder(); folderB.title = "B"; folderB.parentIdentifier = parent.identifier; folderB.index = 1
                let folderC = CPYFolder(); folderC.title = "C"; folderC.parentIdentifier = parent.identifier; folderC.index = 2
                let folderD = CPYFolder(); folderD.title = "D"; folderD.parentIdentifier = parent.identifier; folderD.index = 3
                try! realm.write { realm.add(folderA); realm.add(folderB); realm.add(folderC); realm.add(folderD) }

                let visible: Set<String> = [folderA.identifier, folderC.identifier]
                try! realm.write {
                    NestedMoveExecutor.move(itemId: folderA.identifier, isFolder: true,
                                            toParentId: parent.identifier, atIndex: 1,
                                            visibleIDs: visible, in: realm)
                }

                expect(folderC.index) == 0
                expect(folderD.index) == 1
                expect(folderA.index) == 2
                expect(folderB.index) == 3
            }

            it("nil visibleIDs preserves the existing full-set behaviour") {
                let realm = try! Realm()
                let parent1 = CPYFolder(); parent1.index = 0
                let parent2 = CPYFolder(); parent2.index = 1
                try! realm.write { realm.add(parent1); realm.add(parent2) }
                let snippet = CPYSnippet(); snippet.parentIdentifier = parent1.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }

                try! realm.write {
                    NestedMoveExecutor.move(itemId: snippet.identifier, isFolder: false,
                                            toParentId: parent2.identifier, atIndex: 0,
                                            visibleIDs: nil, in: realm)
                }
                expect(snippet.parentIdentifier) == parent2.identifier
                expect(snippet.index) == 0
            }

            it("hidden item with no preceding visible anchor goes to the front") {
                // Original order: H V1 V2 (indices 0..2). Visible = {V1, V2}.
                // H has no preceding visible -> anchor is nil -> belongs in hiddenAtFront.
                // Move V2 to atIndex=0 in the visible view -> visible becomes [V2, V1].
                // Reconstruction: hiddenAtFront [H] first, then visibleOrdered [V2, V1].
                // Final full order: [H, V2, V1] -> H=0, V2=1, V1=2.
                let realm = try! Realm()
                let parent = CPYFolder(); parent.index = 0
                try! realm.write { realm.add(parent) }
                let hidden = CPYFolder(); hidden.title = "H"; hidden.parentIdentifier = parent.identifier; hidden.index = 0
                let visible1 = CPYFolder(); visible1.title = "V1"; visible1.parentIdentifier = parent.identifier; visible1.index = 1
                let visible2 = CPYFolder(); visible2.title = "V2"; visible2.parentIdentifier = parent.identifier; visible2.index = 2
                try! realm.write { realm.add(hidden); realm.add(visible1); realm.add(visible2) }

                let visibleIDs: Set<String> = [visible1.identifier, visible2.identifier]
                try! realm.write {
                    NestedMoveExecutor.move(itemId: visible2.identifier, isFolder: true,
                                            toParentId: parent.identifier, atIndex: 0,
                                            visibleIDs: visibleIDs, in: realm)
                }
                expect(hidden.index) == 0
                expect(visible2.index) == 1
                expect(visible1.index) == 2
            }
        }
```

- [ ] **Step 2: Build to confirm tests fail to compile**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: FAIL — `Argument 'visibleIDs' must precede argument 'in'` or `Extra argument 'visibleIDs' in call`.

- [ ] **Step 3: Update `NestedMoveExecutor.move` to accept `visibleIDs`**

In `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift`, replace the existing `NestedMoveExecutor.move(...)` method with:

```swift
    static func move(itemId: String,
                     isFolder: Bool,
                     toParentId: String,
                     atIndex: Int,
                     visibleIDs: Set<String>? = nil,
                     in realm: Realm) {
        let oldParentId: String
        if isFolder {
            guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: itemId) else { return }
            oldParentId = folder.parentIdentifier
            folder.parentIdentifier = toParentId
        } else {
            guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: itemId) else { return }
            oldParentId = snippet.parentIdentifier
            snippet.parentIdentifier = toParentId
        }
        let allKids = CPYFolder.children(parentIdentifier: toParentId, in: realm)
        let target: Object?
        if isFolder {
            target = realm.object(ofType: CPYFolder.self, forPrimaryKey: itemId)
        } else {
            target = realm.object(ofType: CPYSnippet.self, forPrimaryKey: itemId)
        }
        let ordered: [Object]
        if let visible = visibleIDs {
            ordered = reorderRespectingHiddenAnchors(allKids: allKids,
                                                    visible: visible,
                                                    movedId: itemId,
                                                    movedItem: target,
                                                    atIndex: atIndex)
        } else {
            var working: [Object] = []
            for kid in allKids where idOf(kid) != itemId { working.append(kid) }
            if let target = target {
                let pos = (atIndex < 0 || atIndex > working.count) ? working.count : atIndex
                working.insert(target, at: pos)
            }
            ordered = working
        }
        for (idx, kid) in ordered.enumerated() {
            if let folder = kid as? CPYFolder { folder.index = idx }
            else if let snippet = kid as? CPYSnippet { snippet.index = idx }
        }
        if oldParentId != toParentId {
            CPYFolder.renumberSiblings(of: oldParentId, in: realm)
        }
    }

    /// Build the new full order while keeping every hidden sibling next to
    /// the same visible neighbour it had before. Each hidden sibling's
    /// "anchor" is the closest visible sibling that came before it in
    /// `allKids`; nil means it was before all visibles. After the moved
    /// item is repositioned within the visible subset, hidden siblings are
    /// re-emitted just after their anchor (or at the front for nil anchors).
    private static func reorderRespectingHiddenAnchors(allKids: [Object],
                                                       visible: Set<String>,
                                                       movedId: String,
                                                       movedItem: Object?,
                                                       atIndex: Int) -> [Object] {
        // Compute hidden anchors from the original order.
        var hiddenByAnchor: [String: [Object]] = [:]   // anchor visible id -> hidden items in original order
        var hiddenAtFront: [Object] = []
        var lastVisibleId: String?
        for kid in allKids {
            let kidId = idOf(kid)
            if visible.contains(kidId) {
                lastVisibleId = kidId
            } else {
                if let anchor = lastVisibleId {
                    hiddenByAnchor[anchor, default: []].append(kid)
                } else {
                    hiddenAtFront.append(kid)
                }
            }
        }
        // Build the new visible ordering with the moved item in place.
        var visibleOrdered: [Object] = []
        for kid in allKids where visible.contains(idOf(kid)) && idOf(kid) != movedId {
            visibleOrdered.append(kid)
        }
        if let movedItem = movedItem {
            let pos = (atIndex < 0 || atIndex > visibleOrdered.count) ? visibleOrdered.count : atIndex
            visibleOrdered.insert(movedItem, at: pos)
        }
        // Reconstruct full order.
        var result: [Object] = []
        result.append(contentsOf: hiddenAtFront)
        for kid in visibleOrdered {
            result.append(kid)
            if let trailing = hiddenByAnchor[idOf(kid)] {
                result.append(contentsOf: trailing)
            }
        }
        return result
    }
```

- [ ] **Step 4: Make `NestedMoveExecutor` use the controller's `idOf` helper**

The existing `NestedMoveExecutor` already has its own `private static func idOf(...)`. Leave it as-is — `private` keeps it scoped to the enum. The `reorderRespectingHiddenAnchors` method above calls the same `idOf(...)` and resolves to the enum's local helper.

- [ ] **Step 5: Pass `visibleIdentifiers` from `acceptDrop`**

In `acceptDrop` (same file), replace the line:

```swift
        try? realm.write {
            NestedMoveExecutor.move(itemId: dragged.identifier,
                                    isFolder: dragged.type == .folder,
                                    toParentId: targetParentId,
                                    atIndex: index,
                                    in: realm)
        }
```

with:

```swift
        try? realm.write {
            NestedMoveExecutor.move(itemId: dragged.identifier,
                                    isFolder: dragged.type == .folder,
                                    toParentId: targetParentId,
                                    atIndex: index,
                                    visibleIDs: visibleIdentifiersForMove(),
                                    in: realm)
        }
```

Add a new accessor on the controller (in `CPYSnippetsEditorWindowController.swift`, somewhere in the main class body) — default access level (internal) so the OutlineDataSource extension in the sibling file can call it:

```swift
    func visibleIdentifiersForMove() -> Set<String>? {
        return visibleIdentifiers
    }
```

- [ ] **Step 6: Build and run tests**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: build succeeds.

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/NestedDragDropSpec`
Expected: all 11 tests pass (8 existing + 3 new).

- [ ] **Step 7: Manual smoke**

Rebuild Release. Open snippets editor with at least 4 sibling folders / snippets at one level. Type a query that filters out the middle ones. Drag a remaining visible item to a new position. Clear the search. Verify the previously hidden items are still in their original relative slots around the visible ones.

- [ ] **Step 8: Commit**

```bash
git add Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift \
        Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift \
        ClipyTests/NestedDragDropSpec.swift
git commit -m "make snippet editor drag-drop honour active search filter"
```

---

## Final verification

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test`
Expected: all tests pass.

- [ ] **Step 2: Build Release and full smoke**

Per `CLAUDE.md`:
```bash
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  CONFIGURATION_BUILD_DIR=/Volumes/dev/code-dev/clipy/build/Release build
```
Quit running Clipy and `open /Volumes/dev/code-dev/clipy/build/Release/Clipy.app`. Walk through the smoke checklist:

1. Open snippets editor, search field visible above outline view.
2. Type fragment of snippet title — tree filters in real time, ancestors auto-expanded.
3. Type fragment of content — same filtering, body match works.
4. Press ⌘F from anywhere in the editor — focus jumps to search field.
5. Esc with text — clears query (focus stays). Esc again — focus moves to outline view.
6. With filter active, drag a visible snippet between visible siblings; clear filter; verify hidden siblings are still in their relative positions.
7. Diacritic/case test: snippet titled "José", query "jose" — match.

- [ ] **Step 3: Confirm git log is clean**

Run: `git log --oneline -6`
Expected: 4 commits in plain imperative English (one per Task 1–4), no AI attribution.

---

## Notes

- **Filter scope decision**: by spec the filter searches snippet `title` + `content`. Folder titles do NOT match. Folders only appear in the visible set as ancestors of matched snippets.
- **State preservation**: the snapshot of expanded folder IDs is taken when the user *first* enters search mode (transition from nil → non-nil filter). Subsequent keystrokes update `visibleIdentifiers` but do not re-snapshot — so when the user finally clears the field, expansion returns to the pre-search state.
- **Hidden-anchor drag-drop** keeps every hidden sibling glued to the visible neighbour that preceded it. The worst-case "wrong" outcome is one slot off — easy to inspect by clearing the filter. Tests cover the canonical case + nil-visibleIDs back-compat + nil-anchor (front).
- **No persisted query**: clearing or closing the editor wipes the filter. Acceptable — same UX as Mail / Finder sidebar search.
