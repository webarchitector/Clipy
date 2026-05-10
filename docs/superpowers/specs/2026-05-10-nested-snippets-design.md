# Nested Snippets — Design

**Date:** 2026-05-10
**Author:** brainstorming session

## Goal

Replace the current two-level snippets hierarchy (folder → snippets) with a tree of folders up to **5 levels deep**, where each folder can hold both snippets and subfolders, freely intermixed by user-defined order.

## Out of scope

- Folder-level inheritance of `enable` (children keep their own flags).
- Folder-level inheritance of hotkeys.
- Visual mockups beyond what `NSOutlineView` already renders.
- Anything outside the snippets feature (history, app launcher, input sources).

## Constraints decided in brainstorming

| # | Decision |
|---|----------|
| 1 | Max depth = 5 levels (root = level 1). |
| 2 | A folder can contain snippets and subfolders mixed; display order is by `index` shared across both. |
| 3 | Menu rendering = native nested submenus, items in user-defined order. |
| 4 | Hotkeys can be assigned to any folder regardless of nesting level. |
| 5 | Data model = parent-pointer (no embedded `List<CPYFolder>`). |
| 6 | Drag-and-drop = standard macOS behavior: drop folder onto folder makes it a child; drop between siblings reorders; cycles and depth violations are rejected. |
| 7 | XML import/export = recursive `<folders>` element inside each `<folder>`; old flat XML still imports correctly. |

## Data model

### Realm schema bump 8 → 9

**`CPYFolder`**
- Removed: `let snippets = List<CPYSnippet>()`
- Added: `@objc dynamic var parentIdentifier = ""` — empty string means root.
- Kept: `index`, `enable`, `title`, `identifier` (primary key).

**`CPYSnippet`**
- Removed: `let folders = LinkingObjects(fromType: CPYFolder.self, property: "snippets")` and the `var folder: CPYFolder?` computed accessor.
- Added: `@objc dynamic var parentIdentifier = ""` — id of the owning folder, always non-empty for live snippets.
- Kept: `index`, `enable`, `title`, `content`, `identifier` (primary key).
- `ignoredProperties()` returns `[]` (no longer needs to hide `folder`).

### Ordering

`index` is unique within one `parentIdentifier` and is shared between snippets and folders that have the same parent. The merged children list is `(folders ∪ snippets where parent==X).sorted(by: index ascending)`. Two siblings never have the same `index`; renumber after every mutation that affects sibling order.

### Depth

Defined for folders only as the count of folders in the chain from the folder up to and including the root. A root folder has depth 1. The deepest allowed folder has depth 5. Snippets are contents of folders, not their own level — they may live in any folder of depth 1..5. Validation runs before any insert or move; on violation: `NSSound.beep()`.

For folder moves, the resulting deepest depth in the moved subtree is `depth(targetParent) + maxDescendantDepth(draggedFolder)`, where `depth(nil) = 0` (root) and `maxDescendantDepth(f)` = the number of folder levels contained in `f` (1 for a leaf folder, 2 for a folder with one level of subfolders, etc.). Reject if this sum > 5.

For snippet moves, the only check is that the target is a folder (not root); snippets don't add a folder level.

### Cycles

A folder may not become a descendant of itself. Cycle check: walk from the proposed new parent upward via `parentIdentifier` until empty; if the moved folder's `identifier` appears, reject.

### Migration block (oldSchemaVersion <= 8)

Two-pass approach within the same migration block:

```
// Pass 1: walk old folders, build [snippetId: folderId] map, mark folders as roots.
var snippetParent: [String: String] = [:]
migration.enumerateObjects(ofType: CPYFolder.className()) { oldFolder, newFolder in
    let folderId = oldFolder!["identifier"] as! String
    newFolder!["parentIdentifier"] = ""
    let oldSnippets = oldFolder!["snippets"] as! List<DynamicObject>
    for oldSnippet in oldSnippets {
        let snippetId = oldSnippet["identifier"] as! String
        snippetParent[snippetId] = folderId
    }
}

// Pass 2: write parentIdentifier into snippets using the map.
migration.enumerateObjects(ofType: CPYSnippet.className()) { _, newSnippet in
    let snippetId = newSnippet!["identifier"] as! String
    newSnippet!["parentIdentifier"] = snippetParent[snippetId] ?? ""
}
```

Two passes are required because Realm migration blocks may process types in any order; the snippet's parent must be discovered from the folder side first. After the block runs, Realm drops the `snippets` property automatically (detected via schema diff).

Snippets that wind up with `parentIdentifier == ""` after pass 2 are orphans (data corruption from earlier versions). They are left in Realm but invisible to the editor and menu — a follow-up cleanup pass is out of scope.

## Editor (`CPYSnippetsEditorWindowController`)

### State

The current `var folders = [CPYFolder]()` (deep-copied unmanaged copies) is replaced by a Realm-backed approach: the controller stores `var rootFolderIDs: [String]` (or queries roots on demand) and reads/writes through Realm directly. Mutations happen in transactions; after each mutation `outlineView.reloadData()` is called.

`CPYFolder.deepCopy()` is retained only for any code that still uses it; it can be left as-is (the recursive case is unused since we no longer need detached copies).

### `NSOutlineViewDataSource`

```
numberOfChildrenOfItem(item):
    item == nil → roots.count
    item is CPYFolder → children(of: item.identifier).count
    else → 0

isItemExpandable(item):
    item is CPYFolder && children(of: item.identifier).count > 0

child(index, ofItem):
    item == nil → roots[index]
    item is CPYFolder → children(of: item.identifier)[index]

objectValueFor(item) → item.title
```

`children(of: id)` is a helper that runs the merged-and-sorted query and caches the result. Cache invalidated explicitly before every `outlineView.reloadData()` call (a small `func reloadOutline() { childrenCache.removeAll(); outlineView.reloadData() }` wrapper centralises this).

### `NSOutlineViewDelegate`

- `willDisplayCell`: nested folders also get `iconType = .folder`.
- Hotkey panel (`folderSettingView`) is shown for any selected `CPYFolder`, regardless of depth.

### IBActions

- **Add Snippet**: insert new `CPYSnippet` into the selected folder (or, if a snippet is selected, into its parent folder). If nothing is selected → beep. New snippet appended at the end of children; renumber helper assigns `index`.
- **Add Folder**: if nothing is selected → create at root. If a folder is selected → create as its child (provided `depth(selectedFolder) < 5`; if `== 5`, beep). If a snippet is selected → create as its sibling (child of the snippet's parent folder, same depth check). New folder appended at the end of children; renumber helper assigns `index`.
- **Delete**: alert as today; deletion of a folder cascades — recursively delete all descendant folders and snippets in one transaction. Hotkey unregister still happens for the deleted folder identifier; descendant folders' hotkeys are also unregistered (walk descendants before delete to collect identifiers).
- **Toggle Enable**: toggles `enable` on the selected item only; no cascade to descendants. (Disabled folder hides entire subtree from menu by virtue of menu builder skipping it.)
- **Import / Export**: see XML section.

### Selection

After any mutation, the outline view selects the affected item (newly created, surviving sibling after delete, or moved item).

## Drag and drop

### `CPYDraggedData`

Renamed/repurposed:

```
class CPYDraggedData: NSObject, NSSecureCoding {
    let type: DragType            // .folder or .snippet
    let identifier: String        // identifier of the dragged item (folder or snippet)
    let parentIdentifier: String  // current parentIdentifier (empty = root)
    let index: Int                // current index within siblings
}
```

Old `folderIdentifier` and `snippetIdentifier` keys are dropped (pasteboard data does not persist across launches; no compat path needed).

### `pasteboardWriterForItem`

Build a `CPYDraggedData` from the dragged item's current Realm row.

### `validateDrop(item, index)`

`item` is the proposed parent (`nil` = root). `index` is the proposed insertion position among parent's children.

Folder drag:
- Reject if dragging onto itself.
- Reject if proposed parent is a descendant of the dragged folder (cycle check).
- Reject if `depth(proposedParent) + maxDescendantDepth(draggedFolder) > 5`. For root, `depth(nil) = 0`.
- Otherwise return `.move`.

Snippet drag:
- Reject if proposed parent is `nil` (snippets cannot live at root).
- No depth check — snippets don't add a folder level; they are valid in any folder of depth 1..5.
- Otherwise return `.move`.

### `acceptDrop(item, index)`

```
newParentId = (item as? CPYFolder)?.identifier ?? ""
newIndex = index >= 0 ? index : children(of: newParentId).count

if newParentId == draggedData.parentIdentifier && newIndex == draggedData.index { return false }

realm.transaction {
    moved = realm.object(ofType: T.self, forPrimaryKey: draggedData.identifier)
    moved.parentIdentifier = newParentId
    // Renumber: collect siblings of new parent excluding moved (or including with adjusted index),
    // assign indices 0..n-1 in the desired order, then if old parent != new parent renumber old
    // parent's remaining siblings 0..m-1.
}

outlineView.reloadData()
if let folder = item as? CPYFolder { outlineView.expandItem(folder) }
outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: moved)), byExtendingSelection: false)
changeItemFocus()
```

Renumber helper: for a given parent id, fetch merged children sorted by current `index`, then assign each item `0..n-1` in iteration order. Runs in the same transaction.

## Menubar popup (`MenuManager.addSnippetItems`)

Rewritten to recurse:

```
func addSnippetItems(_ menu: NSMenu, separateMenu: Bool, settings: MenuSettings) {
    let roots = realm.objects(CPYFolder.self)
        .filter("parentIdentifier == ''")
        .sorted(byKeyPath: "index", ascending: true)
        .filter { $0.enable }
    guard !roots.isEmpty else { return }
    if separateMenu { menu.addItem(.separator()) }
    let labelItem = NSMenuItem(title: L10n.snippet, action: nil); labelItem.isEnabled = false
    menu.addItem(labelItem)
    for root in roots {
        let item = makeSubmenuItem(root.title, isShowIcon: settings.isShowIcon)
        menu.addItem(item)
        appendChildren(item.submenu!, parentId: root.identifier, settings: settings)
    }
}

func appendChildren(_ menu: NSMenu, parentId: String, settings: MenuSettings) {
    let firstIndex = settings.isStartFromZero ? 0 : 1
    var listNumber = firstIndex
    for child in mergedSortedChildren(parentId: parentId, enabledOnly: true) {
        if let folder = child as? CPYFolder {
            let sub = makeSubmenuItem(folder.title, isShowIcon: settings.isShowIcon)
            menu.addItem(sub)
            appendChildren(sub.submenu!, parentId: folder.identifier, settings: settings)
        } else if let snippet = child as? CPYSnippet {
            menu.addItem(makeSnippetMenuItem(snippet, listNumber: listNumber, settings: settings))
            listNumber += 1
        }
    }
}
```

`mergedSortedChildren` returns a `[Any]` of folders and snippets matching `parent==parentId`, optionally filtered by `enable`, sorted by `index`. Stable; ties don't occur (renumber keeps indices unique).

`listNumber` is a per-submenu counter that only advances on snippet items, matching the existing convention (folders are not numbered).

## Hotkeys

`HotKeyService` requires no changes: registry is keyed by `folder.identifier`, which is unique regardless of nesting. When a folder hotkey fires, the popup is built by calling `appendChildren` rooted at that folder's identifier.

## XML import / export

### Constants

Add to `Constants.Xml`:

```
static let foldersElement = "folders"
```

### Export

Recursive: write each folder as today, plus, if it has child folders, append a `<folders>` element containing each child folder recursively. Empty `<folders>` is omitted (cleaner output, more backward-compatible with old importers).

```
func writeFolder(_ folder: CPYFolder, into parent: AEXMLElement) {
    let el = parent.addChild(name: Constants.Xml.folderElement)
    el.addChild(name: Constants.Xml.titleElement, value: folder.title)
    let snippetsEl = el.addChild(name: Constants.Xml.snippetsElement)
    for s in snippetsOf(folder) {
        let sEl = snippetsEl.addChild(name: Constants.Xml.snippetElement)
        sEl.addChild(name: Constants.Xml.titleElement, value: s.title)
        sEl.addChild(name: Constants.Xml.contentElement, value: s.content)
    }
    let children = subfoldersOf(folder)
    if !children.isEmpty {
        let foldersEl = el.addChild(name: Constants.Xml.foldersElement)
        for child in children { writeFolder(child, into: foldersEl) }
    }
}
```

The export iterates roots (sorted by `index`) and calls `writeFolder` for each.

### Import

Recursive: parse each `<folder>` element, create the folder with the right `parentIdentifier`, parse its `<snippets>` (existing logic), then recurse into the inner `<folders>` element if present.

```
func parseFolder(_ element: AEXMLElement, parentId: String, indexCounter: inout Int) {
    let folder = CPYFolder()
    folder.title = element[titleElement].value ?? "untitled folder"
    folder.parentIdentifier = parentId
    folder.index = indexCounter; indexCounter += 1
    realm.add(folder)
    var snippetIndex = 0
    element[snippetsElement][snippetElement].all?.forEach { sEl in
        let s = CPYSnippet()
        s.title = sEl[titleElement].value ?? "untitled snippet"
        s.content = sEl[contentElement].value ?? ""
        s.parentIdentifier = folder.identifier
        s.index = snippetIndex; snippetIndex += 1
        realm.add(s)
    }
    var childIndex = 0
    element[foldersElement][folderElement].all?.forEach { childEl in
        parseFolder(childEl, parentId: folder.identifier, indexCounter: &childIndex)
    }
}
```

For the root, the importer iterates the existing root `<folder>` children of the document root (preserves backward compatibility with v1 flat files — those simply have no inner `<folders>` element, which the recursive call handles gracefully). Imported root folders' `index` continues from `(maxExistingRootIndex + 1)` as today.

## Tests

All in `ClipyTests/`, using Quick + Nimble + RealmSwift in-memory configurations.

- **`RealmMigrationSpec`** (extend): build a v8-schema realm fixture with folders containing snippets via the old `snippets` List; migrate; assert each new snippet has `parentIdentifier = its old folder.identifier` and each folder has `parentIdentifier = ""`.
- **`FolderSpec`** (extend / new tests):
  - `children(of:)` returns folders and snippets merged by `index`.
  - `depth(of:)` returns 1..5 correctly across a 5-level fixture.
  - Helper that creates a child folder returns `nil` when parent depth == 5; the depth check helper is a pure function on the realm — easy to spec.
- **`SnippetSpec`** (extend):
  - Snippet `parentIdentifier` round-trips through Realm.
  - Renumber helper produces 0..n-1 stable order.
- **New `NestedDragDropSpec`** (or extend `DraggedDataSpec`):
  - Cycle prevention: moving folder A into its own descendant returns `.none`.
  - Depth check: moving a 3-deep subtree under a 3-deep parent returns `.none`.
  - Successful move updates `parentIdentifier` and renumbers both old and new parents.
- **New `SnippetXmlRoundTripSpec`**:
  - Build a 3-level tree, export, parse exported XML back, assert isomorphism (titles + contents + nested structure match).
  - Old flat XML fixture parses into a 1-level tree with no children at the leaves.

## Files affected

| File | Change |
|------|--------|
| `Clipy/Sources/Models/CPYFolder.swift` | Drop `snippets`, add `parentIdentifier`, add `children/depth` helpers, drop `mergeSnippet/insertSnippet/removeSnippet/rearrangesSnippetIndex` (replaced by generic renumber helper). |
| `Clipy/Sources/Models/CPYSnippet.swift` | Drop `folders` LinkingObjects + `folder` accessor + ignoredProperties entry, add `parentIdentifier`. |
| `Clipy/Sources/Models/CPYDraggedData.swift` | Replace `folderIdentifier` / `snippetIdentifier` with single `identifier` and `parentIdentifier`. |
| `Clipy/Sources/Extensions/Realm+Migration.swift` | Bump schemaVersion to 9, add migration block (folders pass + snippets pass with id→parentId map). |
| `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift` | Replace `folders` cache with Realm-backed access; rework IBActions for nested adds/deletes/depth checks; show hotkey panel for any folder. |
| `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController+OutlineDataSource.swift` | New data source recursing on `parentIdentifier`; new drop validation with cycle + depth checks; renumber helper. |
| `Clipy/Sources/Managers/MenuManager+MenuBuilders.swift` | Replace `addSnippetItems` with recursive `appendChildren`. |
| `Clipy/Sources/Constants.swift` | Add `Constants.Xml.foldersElement`. |
| `ClipyTests/RealmMigrationSpec.swift` | Add v8→v9 fixture and assertion. |
| `ClipyTests/FolderSpec.swift` | Add depth + children helper specs. |
| `ClipyTests/SnippetSpec.swift` | Add parent-pointer round-trip. |
| `ClipyTests/DraggedDataSpec.swift` | Update for new `CPYDraggedData` shape. |
| `ClipyTests/NestedDragDropSpec.swift` (new) | Cycle, depth, move tests. |
| `ClipyTests/SnippetXmlRoundTripSpec.swift` (new) | XML import/export round-trip; backward compat. |

## Risks

- **Migration data loss** if the two-pass mapping has a bug — mitigated by the migration spec which exercises the path on a real v8 fixture.
- **Realm transaction performance** during cascade delete of large subtrees — acceptable for snippet sizes (typical user has < 100 snippets total).
- **Outline view state** (expansion) is reset on `reloadData()` — acceptable for now; future polish could persist expansion in `UserDefaults`.

## Non-goals

- No UI for moving items via context menu; drag-and-drop is the only move path.
- No bulk import of nested folders from filesystem-style structure.
- No drag-and-drop import from Finder.
