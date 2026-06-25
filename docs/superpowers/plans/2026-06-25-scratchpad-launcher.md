# Scratchpad in the App Launcher — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted scratchpad to the Cmd-Space launcher: stash clipboard text, edit it inline, copy it back, and delete it.

**Architecture:** A new Realm model `CPYScratchNote` with a thin `ScratchpadStore` (CRUD). The launcher shows a `📝 Scratchpad` row as the top result when the query is empty; selecting it hands the panel to a self-contained `ScratchpadController` that renders a notes list and an inline multi-line editor inside the existing panel, becoming the search field's delegate while active. A pure `ScratchTitle` helper derives display titles. AppLauncher only gains the `.scratchpad` item and the enter/leave handoff.

**Tech Stack:** Swift 6, AppKit (NSPanel/NSTableView/NSTextView), RealmSwift, Quick/Nimble.

## Global Constraints

- `SWIFT_VERSION` is 6.0, strict concurrency ON. New shared mutable state must be main-actor or otherwise `Sendable`-safe. Do not capture spec-scoped `var`s across Quick `it` closures — build per-test fixtures.
- Build (Release, stable signing — keeps TCC grants):
  `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release CONFIGURATION_BUILD_DIR=/Users/ank/dev/clipy/build/Release CODE_SIGN_IDENTITY="Clipy Dev" CODE_SIGN_STYLE=Manual build`
  Incremental `build` only — never `clean build`.
- Run one spec: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -only-testing:ClipyTests/<SpecName> test`
- The build currently depends on uncommitted toolchain fixes already present in the working tree (vendor deployment target 12.0, realm-swift 20.0.5, swiftlint 0.64.1). Do not revert them.
- New source files must be added to BOTH the file system AND `Clipy.xcodeproj/project.pbxproj` (no synchronized folders). For each new file mirror an existing peer's four entries — `PBXBuildFile`, `PBXFileReference`, group child, and the target's Sources build-phase entry — using a fresh unique 24-hex id. App-target files mirror `CPYSnippet.swift`; test files mirror `ClipboardHistoryEntrySpec.swift`.
- Commit messages: English, short imperative, NO prefixes (`feat:`/`fix:`), NO `Co-Authored-By` / AI attribution.
- Install to test in the real app (optional, after a task that changes UI):
  `pkill -x Clipy; rm -rf /Applications/Clipy.app && cp -R /Users/ank/dev/clipy/build/Release/Clipy.app /Applications/Clipy.app && open /Applications/Clipy.app`

## File Structure

| File | Responsibility | Created/Modified |
|------|----------------|------------------|
| `Clipy/Sources/AppLauncher/ScratchTitle.swift` | Pure: derive a display title from note content | Create |
| `Clipy/Sources/Models/CPYScratchNote.swift` | Realm model: identifier/content/createdAt/updatedAt | Create |
| `Clipy/Sources/AppLauncher/ScratchpadStore.swift` | CRUD over Realm; no-op when Realm unavailable | Create |
| `Clipy/Sources/AppLauncher/ScratchpadController.swift` | Self-contained list + inline editor hosted in the panel | Create |
| `Clipy/Sources/AppLauncher/ScratchEditorTextView.swift` | NSTextView subclass: ⌘Enter / ⌘⌫ / Esc key handling | Create |
| `Clipy/Sources/AppLauncher/AppLauncher.swift` | `.scratchpad` item, empty-query prepend, enter/leave handoff | Modify |
| `ClipyTests/ScratchTitleSpec.swift` | Tests for `ScratchTitle` | Create |
| `ClipyTests/ScratchpadStoreSpec.swift` | Tests for `ScratchpadStore` CRUD | Create |
| `ClipyTests/LauncherScratchpadItemSpec.swift` | Tests for empty-query prepend helper | Create |

---

### Task 1: `ScratchTitle` pure helper

**Files:**
- Create: `Clipy/Sources/AppLauncher/ScratchTitle.swift`
- Test: `ClipyTests/ScratchTitleSpec.swift`

**Interfaces:**
- Produces: `enum ScratchTitle { static func title(from content: String, maxLength: Int = 60) -> String }` — returns the first non-empty trimmed line of `content`, truncated to `maxLength` with a trailing `…`; returns `""` when there is no non-whitespace text.

- [ ] **Step 1: Write the failing test**

Create `ClipyTests/ScratchTitleSpec.swift`:

```swift
// swiftlint:disable identifier_name
import Quick
import Nimble
@testable import Clipy

class ScratchTitleSpec: QuickSpec {
    override class func spec() {
        describe("ScratchTitle.title(from:)") {
            it("returns empty for blank content") {
                expect(ScratchTitle.title(from: "")).to(equal(""))
                expect(ScratchTitle.title(from: "   \n\n  ")).to(equal(""))
            }
            it("returns the first non-empty trimmed line") {
                expect(ScratchTitle.title(from: "hello")).to(equal("hello"))
                expect(ScratchTitle.title(from: "\n\n  first \nsecond")).to(equal("first"))
                expect(ScratchTitle.title(from: "  spaced  ")).to(equal("spaced"))
            }
            it("truncates long lines with an ellipsis") {
                let long = String(repeating: "a", count: 100)
                let t = ScratchTitle.title(from: long, maxLength: 60)
                expect(t).to(equal(String(repeating: "a", count: 60) + "…"))
            }
        }
    }
}
```

Add the file to `project.pbxproj` (ClipyTests target, mirror `ClipboardHistoryEntrySpec.swift`).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -only-testing:ClipyTests/ScratchTitleSpec test`
Expected: FAIL to compile — `ScratchTitle` is undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Clipy/Sources/AppLauncher/ScratchTitle.swift`:

```swift
import Foundation

enum ScratchTitle {
    static func title(from content: String, maxLength: Int = 60) -> String {
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                if line.count > maxLength {
                    return String(line.prefix(maxLength)) + "…"
                }
                return line
            }
        }
        return ""
    }
}
```

Add the file to `project.pbxproj` (Clipy target, mirror `CPYSnippet.swift`).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -only-testing:ClipyTests/ScratchTitleSpec test`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add Clipy/Sources/AppLauncher/ScratchTitle.swift ClipyTests/ScratchTitleSpec.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add ScratchTitle helper for scratchpad note titles"
```

---

### Task 2: `CPYScratchNote` model + `ScratchpadStore`

**Files:**
- Create: `Clipy/Sources/Models/CPYScratchNote.swift`
- Create: `Clipy/Sources/AppLauncher/ScratchpadStore.swift`
- Test: `ClipyTests/ScratchpadStoreSpec.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `final class CPYScratchNote: Object` with `@objc dynamic var identifier: String` (PK, UUID default), `content: String`, `createdAt: Date`, `updatedAt: Date`.
  - `final class ScratchpadStore` with `init(realmProvider: @escaping () -> Realm? = { Realm.safeInstance() })`, `func allNotes() -> [CPYScratchNote]` (sorted `updatedAt` desc), `@discardableResult func create(content: String) -> String?` (returns new id), `func update(id: String, content: String)`, `func delete(id: String)`, `func note(id: String) -> CPYScratchNote?`. All mutators no-op when the provider returns nil.

Adding a new Realm `Object` subclass is additive — no `schemaVersion` bump or migration block in `Realm+Migration.swift` is required.

- [ ] **Step 1: Write the failing test**

Create `ClipyTests/ScratchpadStoreSpec.swift`:

```swift
// swiftlint:disable identifier_name
import Quick
import Nimble
import RealmSwift
@testable import Clipy

class ScratchpadStoreSpec: QuickSpec {
    override class func spec() {
        describe("ScratchpadStore") {
            func makeRealm() -> Realm {
                let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString,
                                                 objectTypes: [CPYScratchNote.self])
                return try! Realm(configuration: config)
            }

            it("creates and lists notes, newest first") {
                let realm = makeRealm()
                let store = ScratchpadStore(realmProvider: { realm })
                let id1 = store.create(content: "first")
                let id2 = store.create(content: "second")
                expect(id1).toNot(beNil())
                expect(id2).toNot(beNil())
                let notes = store.allNotes()
                expect(notes.count).to(equal(2))
                // newest (last created) first
                expect(notes.first?.identifier).to(equal(id2))
            }

            it("updates content and bumps order to the top") {
                let realm = makeRealm()
                let store = ScratchpadStore(realmProvider: { realm })
                let idA = store.create(content: "A")!
                let idB = store.create(content: "B")!
                store.update(id: idA, content: "A edited")
                let notes = store.allNotes()
                expect(notes.first?.identifier).to(equal(idA))
                expect(store.note(id: idA)?.content).to(equal("A edited"))
                expect(idB).toNot(beNil())
            }

            it("deletes notes") {
                let realm = makeRealm()
                let store = ScratchpadStore(realmProvider: { realm })
                let id = store.create(content: "x")!
                store.delete(id: id)
                expect(store.allNotes().count).to(equal(0))
                expect(store.note(id: id)).to(beNil())
            }

            it("is a no-op when Realm is unavailable") {
                let store = ScratchpadStore(realmProvider: { nil })
                expect(store.create(content: "x")).to(beNil())
                expect(store.allNotes()).to(beEmpty())
                store.update(id: "missing", content: "y")  // must not crash
                store.delete(id: "missing")                // must not crash
            }
        }
    }
}
```

Add the file to `project.pbxproj` (ClipyTests target).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -only-testing:ClipyTests/ScratchpadStoreSpec test`
Expected: FAIL to compile — `CPYScratchNote` / `ScratchpadStore` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Clipy/Sources/Models/CPYScratchNote.swift`:

```swift
import Foundation
import RealmSwift

final class CPYScratchNote: Object {
    @objc dynamic var identifier = UUID().uuidString
    @objc dynamic var content = ""
    @objc dynamic var createdAt = Date()
    @objc dynamic var updatedAt = Date()

    override static func primaryKey() -> String? {
        return "identifier"
    }
}
```

Create `Clipy/Sources/AppLauncher/ScratchpadStore.swift`:

```swift
import Foundation
import RealmSwift

final class ScratchpadStore {
    private let realmProvider: () -> Realm?

    init(realmProvider: @escaping () -> Realm? = { Realm.safeInstance() }) {
        self.realmProvider = realmProvider
    }

    func allNotes() -> [CPYScratchNote] {
        guard let realm = realmProvider() else { return [] }
        return Array(realm.objects(CPYScratchNote.self)
            .sorted(byKeyPath: "updatedAt", ascending: false))
    }

    @discardableResult
    func create(content: String) -> String? {
        guard let realm = realmProvider() else { return nil }
        let note = CPYScratchNote()
        note.content = content
        let now = Date()
        note.createdAt = now
        note.updatedAt = now
        let id = note.identifier
        realm.transaction { realm.add(note) }
        return id
    }

    func update(id: String, content: String) {
        guard let realm = realmProvider(),
              let note = realm.object(ofType: CPYScratchNote.self, forPrimaryKey: id) else { return }
        realm.transaction {
            note.content = content
            note.updatedAt = Date()
        }
    }

    func delete(id: String) {
        guard let realm = realmProvider(),
              let note = realm.object(ofType: CPYScratchNote.self, forPrimaryKey: id) else { return }
        realm.transaction { realm.delete(note) }
    }

    func note(id: String) -> CPYScratchNote? {
        guard let realm = realmProvider() else { return nil }
        return realm.object(ofType: CPYScratchNote.self, forPrimaryKey: id)
    }
}
```

Add both files to `project.pbxproj` (Clipy target).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -only-testing:ClipyTests/ScratchpadStoreSpec test`
Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
git add Clipy/Sources/Models/CPYScratchNote.swift Clipy/Sources/AppLauncher/ScratchpadStore.swift ClipyTests/ScratchpadStoreSpec.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add CPYScratchNote model and ScratchpadStore"
```

---

### Task 3: Launcher `.scratchpad` item + empty-query prepend

**Files:**
- Modify: `Clipy/Sources/AppLauncher/AppLauncher.swift` (enum `LauncherItem`, `applyFilter`, `tableView(_:viewFor:)`)
- Create: `Clipy/Sources/AppLauncher/LauncherItems.swift`
- Test: `ClipyTests/LauncherScratchpadItemSpec.swift`

**Interfaces:**
- Consumes: `ScratchpadStore.allNotes()` (Task 2).
- Produces:
  - New case `LauncherItem.scratchpad(noteCount: Int)`.
  - `enum LauncherItems { static func withScratchpad(prefixing items: [LauncherItem], query: String, noteCount: Int) -> [LauncherItem] }` — prepends `.scratchpad(noteCount:)` iff `query` is empty/whitespace, else returns `items` unchanged.

- [ ] **Step 1: Write the failing test**

Create `ClipyTests/LauncherScratchpadItemSpec.swift`:

```swift
// swiftlint:disable identifier_name
import Quick
import Nimble
@testable import Clipy

class LauncherScratchpadItemSpec: QuickSpec {
    override class func spec() {
        describe("LauncherItems.withScratchpad") {
            it("prepends a scratchpad item when the query is empty") {
                let out = LauncherItems.withScratchpad(prefixing: [.status("x")], query: "  ", noteCount: 3)
                guard case let .scratchpad(noteCount) = out.first else {
                    fail("expected .scratchpad first"); return
                }
                expect(noteCount).to(equal(3))
                expect(out.count).to(equal(2))
            }
            it("leaves results unchanged when the query is non-empty") {
                let out = LauncherItems.withScratchpad(prefixing: [.status("x")], query: "ab", noteCount: 3)
                expect(out.count).to(equal(1))
                if case .scratchpad = out.first { fail("did not expect scratchpad") }
            }
        }
    }
}
```

Add the file to `project.pbxproj` (ClipyTests target).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -only-testing:ClipyTests/LauncherScratchpadItemSpec test`
Expected: FAIL to compile — `LauncherItems` / `.scratchpad` undefined.

- [ ] **Step 3: Write minimal implementation**

In `AppLauncher.swift`, add the case to `LauncherItem`:

```swift
enum LauncherItem {
    case app(name: String, running: Bool)
    case calcCopyResult(expression: String, result: String)
    case calcCopyFull(expression: String, result: String)
    case status(String)
    case scratchpad(noteCount: Int)
}
```

Create `Clipy/Sources/AppLauncher/LauncherItems.swift`:

```swift
import Foundation

enum LauncherItems {
    static func withScratchpad(prefixing items: [LauncherItem],
                               query: String,
                               noteCount: Int) -> [LauncherItem] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        return [.scratchpad(noteCount: noteCount)] + items
    }
}
```

Add `LauncherItems.swift` to `project.pbxproj` (Clipy target).

In `AppLauncher.swift`, add a store property near the other storage:

```swift
    let scratchpadStore = ScratchpadStore()
```

In `applyFilter`, replace `visibleItems = items` with (compute the note count only when the query is empty, to avoid a Realm read on every keystroke):

```swift
        let scratchCount = q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? scratchpadStore.allNotes().count : 0
        visibleItems = LauncherItems.withScratchpad(prefixing: items,
                                                    query: q,
                                                    noteCount: scratchCount)
```

In `tableView(_:viewFor:)`, add a case to the `switch visibleItems[row]`:

```swift
        case let .scratchpad(noteCount):
            tf.stringValue = "📝 Scratchpad (\(noteCount))"
            dotLabel.isHidden = true
```

In `activateSelection`, add a case (temporary — wired fully in Task 6):

```swift
        case .scratchpad:
            break
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -only-testing:ClipyTests/LauncherScratchpadItemSpec test`
Expected: PASS (2 examples).

- [ ] **Step 5: Build and commit**

```bash
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release CONFIGURATION_BUILD_DIR=/Users/ank/dev/clipy/build/Release CODE_SIGN_IDENTITY="Clipy Dev" CODE_SIGN_STYLE=Manual build
git add Clipy/Sources/AppLauncher/AppLauncher.swift Clipy/Sources/AppLauncher/LauncherItems.swift ClipyTests/LauncherScratchpadItemSpec.swift Clipy.xcodeproj/project.pbxproj
git commit -m "show scratchpad entry atop launcher results when query empty"
```

---

### Task 4: `ScratchEditorTextView` (editor key handling)

**Files:**
- Create: `Clipy/Sources/AppLauncher/ScratchEditorTextView.swift`

**Interfaces:**
- Produces: `final class ScratchEditorTextView: NSTextView` exposing `var onCommandEnter: (() -> Void)?`, `var onDeleteNote: (() -> Void)?`, `var onCancel: (() -> Void)?`. It calls `onCommandEnter` for ⌘Return, `onDeleteNote` for ⌘Delete, and `onCancel` for Escape; all other keys behave as a normal multi-line text view.

This task is verified by build + manual check (no unit test — it needs a live first responder).

- [ ] **Step 1: Write the implementation**

Create `Clipy/Sources/AppLauncher/ScratchEditorTextView.swift`:

```swift
import Cocoa

final class ScratchEditorTextView: NSTextView {
    var onCommandEnter: (() -> Void)?
    var onDeleteNote: (() -> Void)?
    var onCancel: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command {
            switch event.charactersIgnoringModifiers {
            case "\r":
                onCommandEnter?()
                return true
            case String(UnicodeScalar(NSDeleteCharacter)!), "\u{7f}", "\u{8}":
                onDeleteNote?()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the Release build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Clipy/Sources/AppLauncher/ScratchEditorTextView.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add ScratchEditorTextView with cmd-enter, cmd-delete, esc handling"
```

---

### Task 5: `ScratchpadController` (list + inline editor)

**Files:**
- Create: `Clipy/Sources/AppLauncher/ScratchpadController.swift`

**Interfaces:**
- Consumes: `ScratchpadStore` (Task 2), `ScratchTitle` (Task 1), `ScratchEditorTextView` (Task 4).
- Produces: `@MainActor final class ScratchpadController: NSObject` with:
  - `init(store: ScratchpadStore, copyToPasteboard: @escaping (String) -> Void, hidePanel: @escaping () -> Void, exitToRoot: @escaping () -> Void)`
  - `func enter(contentView: NSView, searchField: NSSearchField, launcherScroll: NSView)` — hides `launcherScroll`, installs its own list view, becomes `searchField.delegate`, shows the notes list, returns the panel's desired content height via `onHeightChange`.
  - `func leave()` — removes its views, unhides `launcherScroll`, restores nothing (caller re-sets the searchField delegate).
  - `var onHeightChange: ((CGFloat) -> Void)?`
  - It implements `NSSearchFieldDelegate`, `NSTableViewDataSource`, `NSTableViewDelegate` for the list, and wires `ScratchEditorTextView` callbacks for the editor.

Verified by build + manual check.

- [ ] **Step 1: Write the implementation**

Create `Clipy/Sources/AppLauncher/ScratchpadController.swift`:

```swift
import Cocoa

@MainActor
final class ScratchpadController: NSObject, NSSearchFieldDelegate,
                                  NSTableViewDataSource, NSTableViewDelegate {

    private enum Mode { case list, editor }

    private let store: ScratchpadStore
    private let copyToPasteboard: (String) -> Void
    private let hidePanel: () -> Void
    private let exitToRoot: () -> Void

    var onHeightChange: ((CGFloat) -> Void)?

    private weak var contentView: NSView?
    private weak var searchField: NSSearchField?
    private weak var launcherScroll: NSView?

    private var mode: Mode = .list
    private var notes: [CPYScratchNote] = []          // filtered list (excludes the "new" row)
    private var editingId: String?

    // List UI
    private var listScroll: NSScrollView?
    private var listTable: NSTableView?
    // Editor UI
    private var editorScroll: NSScrollView?
    private var editorTextView: ScratchEditorTextView?

    private static let newRowTitle = "➕ New from clipboard"

    init(store: ScratchpadStore,
         copyToPasteboard: @escaping (String) -> Void,
         hidePanel: @escaping () -> Void,
         exitToRoot: @escaping () -> Void) {
        self.store = store
        self.copyToPasteboard = copyToPasteboard
        self.hidePanel = hidePanel
        self.exitToRoot = exitToRoot
    }

    // MARK: - Enter / leave

    func enter(contentView: NSView, searchField: NSSearchField, launcherScroll: NSView) {
        self.contentView = contentView
        self.searchField = searchField
        self.launcherScroll = launcherScroll
        launcherScroll.isHidden = true
        searchField.stringValue = ""
        searchField.placeholderString = "Search scratchpad…"
        searchField.delegate = self
        showList(filter: "")
    }

    func leave() {
        teardownList()
        teardownEditor()
        launcherScroll?.isHidden = false
        searchField?.isHidden = false
        searchField?.placeholderString = "App, math (`(1+2)=`), or currency (`15 usd thb=`)"
    }

    // MARK: - List

    private func showList(filter: String) {
        mode = .list
        teardownEditor()
        searchField?.isHidden = false
        reloadNotes(filter: filter)

        guard let contentView = contentView else { return }
        if listScroll == nil {
            let table = NSTableView()
            table.dataSource = self
            table.delegate = self
            table.headerView = nil
            table.rowHeight = 24
            table.style = .plain
            table.intercellSpacing = NSSize(width: 0, height: 2)
            table.target = self
            table.action = #selector(listRowClicked)
            table.doubleAction = #selector(listRowClicked)
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("scratch"))
            col.width = 580
            table.addTableColumn(col)

            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.borderType = .noBorder
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(scroll)
            if let sf = searchField {
                NSLayoutConstraint.activate([
                    scroll.topAnchor.constraint(equalTo: sf.bottomAnchor, constant: 6),
                    scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
                    scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
                    scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
                ])
            }
            self.listScroll = scroll
            self.listTable = table
        }
        listScroll?.isHidden = false
        listTable?.reloadData()
        if (listTable?.numberOfRows ?? 0) > 0 {
            listTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        emitHeight(rows: (notes.count + 1))
    }

    private func reloadNotes(filter: String) {
        let all = store.allNotes()
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        notes = q.isEmpty ? all : all.filter { $0.content.lowercased().contains(q) }
    }

    private func teardownList() {
        listScroll?.removeFromSuperview()
        listScroll = nil
        listTable = nil
    }

    @objc private func listRowClicked() {
        activateListSelection()
    }

    func activateListSelection() {
        guard let row = listTable?.selectedRow, row >= 0 else { return }
        if row == 0 {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            if let id = store.create(content: clip) { openEditor(id: id) }
            return
        }
        let noteIndex = row - 1
        guard noteIndex < notes.count else { return }
        openEditor(id: notes[noteIndex].identifier)
    }

    // MARK: - Editor

    private func openEditor(id: String) {
        mode = .editor
        editingId = id
        teardownList()
        searchField?.isHidden = true

        guard let contentView = contentView else { return }
        let textView = ScratchEditorTextView()
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.string = store.note(id: id)?.content ?? ""
        textView.delegate = self
        textView.onCancel = { [weak self] in self?.saveAndShowList() }
        textView.onCommandEnter = { [weak self] in self?.copyCurrentAndHide() }
        textView.onDeleteNote = { [weak self] in self?.deleteCurrentAndShowList() }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
        self.editorScroll = scroll
        self.editorTextView = textView
        contentView.window?.makeFirstResponder(textView)
        onHeightChange?(320)
    }

    private func teardownEditor() {
        flushEditorSave()
        editorScroll?.removeFromSuperview()
        editorScroll = nil
        editorTextView = nil
    }

    private func flushEditorSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard let id = editingId, let tv = editorTextView else { return }
        store.update(id: id, content: tv.string)
    }

    private func saveAndShowList() {
        flushEditorSave()
        editingId = nil
        showList(filter: "")
    }

    private func copyCurrentAndHide() {
        flushEditorSave()
        if let tv = editorTextView { copyToPasteboard(tv.string) }
        hidePanel()
    }

    private func deleteCurrentAndShowList() {
        if let id = editingId { store.delete(id: id) }
        editingId = nil
        teardownEditor()
        showList(filter: "")
    }

    // MARK: - Height

    private func emitHeight(rows: Int) {
        let rowH: CGFloat = 24 + 2
        let chrome: CGFloat = 8 + 28 + 6 + 8
        onHeightChange?(chrome + CGFloat(max(1, rows)) * rowH + 4)
    }

    // MARK: - NSTableView (list)

    func numberOfRows(in tableView: NSTableView) -> Int { notes.count + 1 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("scratchCell"), owner: self)
                    as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("scratchCell")
        let tf = cell.textField ?? {
            let f = NSTextField(labelWithString: "")
            f.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(f)
            cell.textField = f
            NSLayoutConstraint.activate([
                f.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                f.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                f.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return f
        }()
        tf.font = NSFont.systemFont(ofSize: 14)
        tf.lineBreakMode = .byTruncatingTail
        if row == 0 {
            tf.stringValue = Self.newRowTitle
            tf.textColor = .secondaryLabelColor
        } else {
            let note = notes[row - 1]
            let title = ScratchTitle.title(from: note.content)
            tf.stringValue = title.isEmpty ? "Empty note" : title
            tf.textColor = .labelColor
        }
        return cell
    }

    // MARK: - NSSearchFieldDelegate (list filtering + keys)

    func controlTextDidChange(_ obj: Notification) {
        guard mode == .list else { return }
        reloadNotes(filter: searchField?.stringValue ?? "")
        listTable?.reloadData()
        if (listTable?.numberOfRows ?? 0) > 0 {
            listTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        emitHeight(rows: notes.count + 1)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard mode == .list else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            activateListSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if !(searchField?.stringValue.isEmpty ?? true) {
                searchField?.stringValue = ""
                controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            } else {
                exitToRoot()
            }
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveListSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveListSelection(by: -1)
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            return false  // let the field editor delete characters
        default:
            return false
        }
    }

    private func moveListSelection(by delta: Int) {
        guard let table = listTable else { return }
        let count = table.numberOfRows
        guard count > 0 else { return }
        var next = table.selectedRow + delta
        next = max(0, min(count - 1, next))
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }
}

extension ScratchpadController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard mode == .editor else { return }
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushEditorSave() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400), execute: work)
    }
}
```

Add the debounce token alongside the other editor properties (the `flushEditorSave()` above already cancels it so the debounced and explicit saves don't double-fire):

```swift
    private var saveWorkItem: DispatchWorkItem?
```

- [ ] **Step 2: Build to verify it compiles**

Run the Release build command. Expected: `** BUILD SUCCEEDED **`.
(Note: `⌘C`-from-list and "delete selected from list" are wired in Task 6 where AppLauncher routes those keys; the editor's ⌘C/⌘⌫ work here via `ScratchEditorTextView`.)

- [ ] **Step 3: Commit**

```bash
git add Clipy/Sources/AppLauncher/ScratchpadController.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add ScratchpadController with notes list and inline editor"
```

---

### Task 6: Wire AppLauncher ↔ ScratchpadController + list ⌘C/⌘⌫

**Files:**
- Modify: `Clipy/Sources/AppLauncher/AppLauncher.swift`

**Interfaces:**
- Consumes: `ScratchpadController` (Task 5), `scratchpadStore` (Task 3).
- Produces: launcher enters scratchpad mode when `.scratchpad` is activated; routes `⌘C` / `⌘⌫` while in the scratchpad list; resizes the panel via `onHeightChange`; exits back to root.

Verified by build + manual check (full flow).

- [ ] **Step 1: Add controller + mode state to AppLauncher**

Near `scratchpadStore`:

```swift
    private lazy var scratchpad = ScratchpadController(
        store: scratchpadStore,
        copyToPasteboard: { [weak self] s in self?.copyToPasteboard(s) },
        hidePanel: { [weak self] in self?.hide() },
        exitToRoot: { [weak self] in self?.exitScratchpad() }
    )
    private var inScratchpad = false
```

In `setupPanel`, after `self.tableView = tv`, capture the scroll view for handoff. Change the local `let scroll = NSScrollView()` to also store it:

```swift
        self.launcherScroll = scroll
```

And add the property near the others:

```swift
    private var launcherScroll: NSScrollView!
```

- [ ] **Step 2: Implement enter/exit and height callback**

Add to AppLauncher:

```swift
    private func enterScratchpad() {
        guard let content = panel?.contentView, let sf = searchField else { return }
        inScratchpad = true
        scratchpad.onHeightChange = { [weak self] h in self?.setContentHeight(h) }
        scratchpad.enter(contentView: content, searchField: sf, launcherScroll: launcherScroll)
    }

    private func exitScratchpad() {
        inScratchpad = false
        scratchpad.leave()
        searchField?.delegate = self
        searchField?.stringValue = ""
        applyFilter("")
    }

    private func setContentHeight(_ contentHeight: CGFloat) {
        guard let panel = panel else { return }
        let frame = panel.frame
        let chrome = frame.height - panel.contentRect(forFrameRect: frame).height
        let target = contentHeight + chrome
        let top = frame.maxY
        panel.setFrame(NSRect(x: frame.origin.x, y: top - target,
                              width: frame.width, height: target),
                       display: true, animate: false)
    }
```

- [ ] **Step 3: Route activation and list keys**

In `activateSelection`, replace the `case .scratchpad: break` from Task 3 with:

```swift
        case .scratchpad:
            enterScratchpad()
```

No change is needed in AppLauncher's `control(_:textView:doCommandBy:)`: while in scratchpad mode the search field's delegate is the `ScratchpadController`, so AppLauncher's delegate methods are not invoked. The list's `⌘⌫` (delete note) is handled in the controller; the list's `⌘C` (copy note) is handled by a local key monitor (below, since the field editor consumes plain command selectors).

In `ScratchpadController.control(...)` `.list` switch, add a case before `default`:

```swift
        case #selector(NSResponder.deleteToBeginningOfLine(_:)):
            // ⌘⌫ in the list deletes the selected note
            deleteSelectedFromList()
            return true
```

…and implement in `ScratchpadController`:

```swift
    private func deleteSelectedFromList() {
        guard let row = listTable?.selectedRow, row > 0 else { return }
        let idx = row - 1
        guard idx < notes.count else { return }
        store.delete(id: notes[idx].identifier)
        reloadNotes(filter: searchField?.stringValue ?? "")
        listTable?.reloadData()
        emitHeight(rows: notes.count + 1)
    }
```

For `⌘C` in the list, add a key monitor in `enter(...)` (the field editor consumes plain selectors, so use a local monitor scoped to list mode):

```swift
    private var keyMonitor: Any?
```

In `enter(...)` end:

```swift
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.mode == .list else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command, event.charactersIgnoringModifiers == "c" {
                if let row = self.listTable?.selectedRow, row > 0, row - 1 < self.notes.count {
                    self.copyToPasteboard(self.notes[row - 1].content)
                    self.hidePanel()
                    return nil
                }
            }
            return event
        }
```

In `leave()` start:

```swift
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
```

- [ ] **Step 4: Build**

Run the Release build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification**

Install (Global Constraints install command), then:
1. Press Cmd-Space with empty query → `📝 Scratchpad (N)` is the top row.
2. Enter → notes list with `➕ New from clipboard` on top.
3. Copy some text elsewhere, choose `➕ New from clipboard` → editor opens with that text.
4. Edit → `Esc` → back to list; reopen → edit persisted.
5. In editor `⌘Enter` → panel hides, paste elsewhere → edited text present.
6. Reopen note, `⌘⌫` → note removed, back to list.
7. In list, select a note, `⌘C` → panel hides, paste → that note’s text.
8. In list with a filter typed, `Esc` clears filter; `Esc` again returns to the normal launcher (apps/math/currency still work).
9. Quit and relaunch Clipy → notes still present.

- [ ] **Step 6: Commit**

```bash
git add Clipy/Sources/AppLauncher/AppLauncher.swift Clipy/Sources/AppLauncher/ScratchpadController.swift
git commit -m "wire scratchpad mode into launcher with list and editor navigation"
```

---

## Notes for the implementer

- `LauncherPanel` is the existing NSPanel subclass; do not replace it.
- Keep `// swiftlint:disable identifier_name` at the top of new test files (the suite uses short names like `i`).
- If the build ever reports a missing Realm class at runtime, confirm `CPYScratchNote` compiles into the Clipy target (pbxproj membership) — Realm discovers `Object` subclasses automatically; no migration is needed.
- The editor uses a fixed 320 px height for simplicity; growing-to-fit can be a later refinement (out of scope).
