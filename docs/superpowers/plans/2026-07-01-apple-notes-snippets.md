# Apple Notes Snippet Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Preferences option to source snippets either natively (current behavior) or read-only from a chosen Apple Notes folder, mapping its subfolders/notes into the snippet menu.

**Architecture:** Notes are read via AppleScript, flattened to the tree-depth limit, and imported into a dedicated cache Realm file (`apple-notes-snippets.realm`) that mirrors the native `CPYFolder`/`CPYSnippet` schema. The native snippet Realm is never touched. A source switch (`SnippetSourceStore`) routes the menu builder, popup, and paste lookup to `activeSnippetRealm()`. The snippet editor becomes read-only in Apple Notes mode.

**Tech Stack:** Swift 6 (strict concurrency), RealmSwift, Cocoa/AppKit, NSAppleScript, Quick/Nimble tests.

## Global Constraints

- `SWIFT_VERSION` is 6.0 — strict concurrency on. New cross-thread value types must be `Sendable`; never pass Realm objects or `NSMenuItem`/`NSImage` across threads.
- Build only with the workspace, incremental (never `clean build`):
  `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
- Always build before committing; never commit code that doesn't compile.
- Commit messages: English, short imperative, no prefixes, no AI/Co-Authored-By trailer. One logical change per commit.
- Do NOT change the `~/.local/share/app-launcher/var/apps.txt` format or `NetworkIsolation.allowedHosts`.
- No per-folder hotkeys in Apple Notes mode (Notes folder identifiers are unstable across rebuilds).
- Tests use Quick/Nimble with an in-memory Realm set via `Realm.Configuration.defaultConfiguration.inMemoryIdentifier` in `beforeEach`.

## File Structure

**New files:**
- `Clipy/Sources/Snippets/SnippetSource.swift` — `SnippetSource` enum + `SnippetSourceStore` (reads/writes defaults).
- `Clipy/Sources/Snippets/AppleNotesModel.swift` — `NotesFolderNode`, `NotesSnippetNode` Sendable value types + `AppleNotesError`, `AppleNotesSummary`.
- `Clipy/Sources/Snippets/AppleNotesSnippetCache.swift` — cache Realm configuration + accessor.
- `Clipy/Sources/Snippets/AppleNotesImporter.swift` — depth flatten + rebuild cache Realm from a `NotesFolderNode`.
- `Clipy/Sources/Snippets/AppleNotesScripting.swift` — `AppleNotesScripting` protocol, `NotesOutputParser`, `AppleScriptNotesScripting`.
- `Clipy/Sources/Services/AppleNotesService.swift` — orchestration; registered in `Environment`.
- `Clipy/Sources/Preferences/Panels/CPYSnippetPreferenceViewController.swift` + `Base.lproj/CPYSnippetPreferenceViewController.xib` — the Snippets pane.
- Tests: `ClipyTests/SnippetSourceStoreSpec.swift`, `ClipyTests/AppleNotesImporterSpec.swift`, `ClipyTests/NotesOutputParserSpec.swift`, `ClipyTests/AppleNotesServiceSpec.swift`, `ClipyTests/SnippetMenuRoutingSpec.swift`.

**Modified files:**
- `Clipy/Sources/Constants.swift` — new UserDefaults keys.
- `Clipy/Sources/Utility/CPYUtilities.swift` — register defaults.
- `Clipy/Sources/Environments/Environment.swift` + `AppEnvironment.swift` — add `appleNotesService`.
- `Clipy/Sources/Managers/MenuManager.swift` — `activeSnippetRealm()`, `rebuildSnippetSource()`, popup routing.
- `Clipy/Sources/Managers/MenuManager+MenuBuilders.swift` — `addSnippetItems` routing.
- `Clipy/Sources/AppDelegate.swift` — paste lookup routing + refresh-on-launch.
- `Clipy/Sources/Preferences/CPYPreferencesWindowController.swift` + its XIB — add Snippets tab.
- `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift` — read-only mode + banner.

---

### Task 1: UserDefaults keys + registration

**Files:**
- Modify: `Clipy/Sources/Constants.swift:40-68`
- Modify: `Clipy/Sources/Utility/CPYUtilities.swift:36-43`

**Interfaces:**
- Produces: `Constants.UserDefaults.snippetSource` (String key `"kCPYSnippetSource"`), `Constants.UserDefaults.appleNotesFolder` (String key `"kCPYAppleNotesFolder"`). Default registered value for `snippetSource` is `0`.

- [ ] **Step 1: Add the two keys**

In `Constants.UserDefaults` (after `showColorPreviewInTheMenu` on line 67):

```swift
        static let showColorPreviewInTheMenu = "kCPYPrefShowColorPreviewInTheMenu"
        static let snippetSource = "kCPYSnippetSource"
        static let appleNotesFolder = "kCPYAppleNotesFolder"
```

- [ ] **Step 2: Register default source = native (0)**

In `CPYUtilities.registerUserDefaultKeys()`, add under the `/* General */` block (after line 43):

```swift
        defaultValues.updateValue(NSNumber(value: 0), forKey: Constants.UserDefaults.snippetSource)
```

- [ ] **Step 3: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Clipy/Sources/Constants.swift Clipy/Sources/Utility/CPYUtilities.swift
git commit -m "add snippet source user defaults keys"
```

---

### Task 2: SnippetSource enum + store

**Files:**
- Create: `Clipy/Sources/Snippets/SnippetSource.swift`
- Test: `ClipyTests/SnippetSourceStoreSpec.swift`

**Interfaces:**
- Consumes: `Constants.UserDefaults.snippetSource`, `.appleNotesFolder`, `AppEnvironment.current.defaults`.
- Produces:
  - `enum SnippetSource: Int { case native = 0; case appleNotes = 1 }`
  - `enum SnippetSourceStore` with `static var current: SnippetSource { get set }`, `static var appleNotesFolder: String? { get set }`.

- [ ] **Step 1: Write the failing test**

Create `ClipyTests/SnippetSourceStoreSpec.swift`:

```swift
import Quick
import Nimble
import Foundation
@testable import Clipy

class SnippetSourceStoreSpec: QuickSpec {
    override class func spec() {
        var defaults: UserDefaults!

        beforeEach {
            defaults = UserDefaults(suiteName: "SnippetSourceStoreSpec-\(NSUUID().uuidString)")
            AppEnvironment.replaceCurrent(environment: Environment(defaults: defaults))
        }

        it("defaults to native when unset") {
            expect(SnippetSourceStore.current) == SnippetSource.native
        }

        it("round-trips the selected source") {
            SnippetSourceStore.current = .appleNotes
            expect(SnippetSourceStore.current) == SnippetSource.appleNotes
            expect(defaults.integer(forKey: Constants.UserDefaults.snippetSource)) == 1
        }

        it("round-trips the selected folder name") {
            SnippetSourceStore.appleNotesFolder = "Snippets"
            expect(SnippetSourceStore.appleNotesFolder) == "Snippets"
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/SnippetSourceStoreSpec`
Expected: FAIL — `SnippetSourceStore` / `SnippetSource` unresolved.

- [ ] **Step 3: Write the implementation**

Create `Clipy/Sources/Snippets/SnippetSource.swift`:

```swift
import Foundation

enum SnippetSource: Int {
    case native = 0
    case appleNotes = 1
}

enum SnippetSourceStore {
    static var current: SnippetSource {
        get {
            let raw = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.snippetSource)
            return SnippetSource(rawValue: raw) ?? .native
        }
        set {
            AppEnvironment.current.defaults.set(newValue.rawValue, forKey: Constants.UserDefaults.snippetSource)
        }
    }

    static var appleNotesFolder: String? {
        get {
            let name = AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.appleNotesFolder)
            return (name?.isEmpty == false) ? name : nil
        }
        set {
            AppEnvironment.current.defaults.set(newValue ?? "", forKey: Constants.UserDefaults.appleNotesFolder)
        }
    }
}
```

- [ ] **Step 4: Add the file to the Clipy target**

Open `Clipy.xcodeproj` in Xcode (or verify via build). The file must be a member of the `Clipy` target. If building from CLI, confirm it compiles in the next step; if not auto-added, add it with the Xcode project navigator (drag into `Clipy/Sources/Snippets`, check "Clipy" target).

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/SnippetSourceStoreSpec`
Expected: PASS (3 examples).

- [ ] **Step 6: Commit**

```bash
git add Clipy/Sources/Snippets/SnippetSource.swift ClipyTests/SnippetSourceStoreSpec.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add snippet source store"
```

---

### Task 3: Apple Notes value model

**Files:**
- Create: `Clipy/Sources/Snippets/AppleNotesModel.swift`

**Interfaces:**
- Produces:
  - `struct NotesSnippetNode: Sendable, Equatable { let title: String; let content: String }`
  - `struct NotesFolderNode: Sendable, Equatable { let title: String; var snippets: [NotesSnippetNode]; var subfolders: [NotesFolderNode] }`
  - `struct AppleNotesSummary: Sendable, Equatable { let folderCount: Int; let snippetCount: Int }`
  - `enum AppleNotesError: Error, Equatable { case notAuthorized; case notesUnavailable; case folderNotFound; case scriptFailed(String) }`

- [ ] **Step 1: Create the model file**

Create `Clipy/Sources/Snippets/AppleNotesModel.swift`:

```swift
import Foundation

struct NotesSnippetNode: Sendable, Equatable {
    let title: String
    let content: String
}

struct NotesFolderNode: Sendable, Equatable {
    let title: String
    var snippets: [NotesSnippetNode]
    var subfolders: [NotesFolderNode]
}

struct AppleNotesSummary: Sendable, Equatable {
    let folderCount: Int
    let snippetCount: Int
}

enum AppleNotesError: Error, Equatable {
    case notAuthorized
    case notesUnavailable
    case folderNotFound
    case scriptFailed(String)
}
```

- [ ] **Step 2: Build (also add file to target)**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: BUILD SUCCEEDED. If unresolved, add the file to the `Clipy` target in Xcode, then rebuild.

- [ ] **Step 3: Commit**

```bash
git add Clipy/Sources/Snippets/AppleNotesModel.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add apple notes value model"
```

---

### Task 4: Cache Realm configuration

**Files:**
- Create: `Clipy/Sources/Snippets/AppleNotesSnippetCache.swift`

**Interfaces:**
- Consumes: `CPYUtilities.applicationSupportFolder()`, `CPYUtilities.prepareSaveToPath(_:)`, RealmSwift.
- Produces:
  - `enum AppleNotesSnippetCache` with `static func configuration() -> Realm.Configuration` and `static func realm() -> Realm?`.

- [ ] **Step 1: Create the cache accessor**

Create `Clipy/Sources/Snippets/AppleNotesSnippetCache.swift`:

```swift
import Foundation
import os
import RealmSwift

private let cacheLog = Logger(subsystem: "com.clipy-app.Clipy", category: "apple-notes-cache")

enum AppleNotesSnippetCache {
    static func fileURL() -> URL {
        let folder = CPYUtilities.applicationSupportFolder()
        _ = CPYUtilities.prepareSaveToPath(folder)
        return URL(fileURLWithPath: folder).appendingPathComponent("apple-notes-snippets.realm")
    }

    static func configuration() -> Realm.Configuration {
        // Separate file + explicit object types so this cache never shares
        // state or migrations with the native default Realm.
        return Realm.Configuration(fileURL: fileURL(),
                                   schemaVersion: 1,
                                   objectTypes: [CPYFolder.self, CPYSnippet.self])
    }

    static func realm() -> Realm? {
        do {
            return try Realm(configuration: configuration())
        } catch {
            cacheLog.error("Apple Notes cache Realm init failed: \(error.localizedDescription, privacy: .public)")
            assertionFailure("Apple Notes cache Realm init failed: \(error)")
            return nil
        }
    }
}
```

- [ ] **Step 2: Build (add file to target)**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Clipy/Sources/Snippets/AppleNotesSnippetCache.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add apple notes cache realm configuration"
```

---

### Task 5: Importer (depth flatten + rebuild)

**Files:**
- Create: `Clipy/Sources/Snippets/AppleNotesImporter.swift`
- Test: `ClipyTests/AppleNotesImporterSpec.swift`

**Interfaces:**
- Consumes: `NotesFolderNode`, `NotesSnippetNode`, `CPYFolder`, `CPYSnippet`, RealmSwift.
- Produces:
  - `enum AppleNotesImporter`
  - `static let maxFolderDepth = 5`
  - `static func flatten(_ folder: NotesFolderNode, maxDepth: Int = maxFolderDepth) -> NotesFolderNode` — beyond `maxDepth`, deeper subfolders are removed and every snippet in the collapsed subtree is appended to the folder that sits at `maxDepth`.
  - `static func rebuild(from folder: NotesFolderNode, into realm: Realm) -> AppleNotesSummary` — wipes `CPYFolder`/`CPYSnippet` in `realm`, writes `folder` as a single enabled root, returns counts.

- [ ] **Step 1: Write the failing test**

Create `ClipyTests/AppleNotesImporterSpec.swift`:

```swift
import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class AppleNotesImporterSpec: QuickSpec {
    override class func spec() {
        var realm: Realm!

        beforeEach {
            var config = Realm.Configuration.defaultConfiguration
            config.inMemoryIdentifier = NSUUID().uuidString
            realm = try! Realm(configuration: config)
        }

        describe("flatten") {
            it("collapses folders deeper than maxDepth, lifting their snippets") {
                // depth: root(1) > a(2) > b(3) — with maxDepth 2, b is removed and its
                // snippet is appended to a.
                let b = NotesFolderNode(title: "b",
                                        snippets: [NotesSnippetNode(title: "deep", content: "D")],
                                        subfolders: [])
                let a = NotesFolderNode(title: "a", snippets: [], subfolders: [b])
                let root = NotesFolderNode(title: "root", snippets: [], subfolders: [a])

                let flat = AppleNotesImporter.flatten(root, maxDepth: 2)
                expect(flat.subfolders.count) == 1
                let flatA = flat.subfolders[0]
                expect(flatA.title) == "a"
                expect(flatA.subfolders).to(beEmpty())
                expect(flatA.snippets.map { $0.title }) == ["deep"]
            }
        }

        describe("rebuild") {
            it("writes the folder as a single enabled root with mapped children") {
                let sub = NotesFolderNode(title: "Sub",
                                          snippets: [NotesSnippetNode(title: "y", content: "Y")],
                                          subfolders: [])
                let root = NotesFolderNode(title: "Snippets",
                                           snippets: [NotesSnippetNode(title: "x", content: "X")],
                                           subfolders: [sub])

                let summary = AppleNotesImporter.rebuild(from: root, into: realm)
                expect(summary.folderCount) == 2
                expect(summary.snippetCount) == 2

                let roots = realm.objects(CPYFolder.self).filter("parentIdentifier == ''")
                expect(roots.count) == 1
                let rootFolder = roots.first!
                expect(rootFolder.title) == "Snippets"
                expect(rootFolder.enable) == true

                let kids = CPYFolder.children(parentIdentifier: rootFolder.identifier, in: realm)
                // Folders sort before snippets only by index; both start at 0 here,
                // so assert by membership.
                let kidFolders = kids.compactMap { $0 as? CPYFolder }
                let kidSnippets = kids.compactMap { $0 as? CPYSnippet }
                expect(kidFolders.map { $0.title }) == ["Sub"]
                expect(kidSnippets.map { $0.title }) == ["x"]
                expect(kidSnippets.first?.content) == "X"
            }

            it("wipes the previous cache on each rebuild") {
                let first = NotesFolderNode(title: "Old", snippets: [], subfolders: [])
                _ = AppleNotesImporter.rebuild(from: first, into: realm)
                let second = NotesFolderNode(title: "New",
                                             snippets: [NotesSnippetNode(title: "n", content: "N")],
                                             subfolders: [])
                let summary = AppleNotesImporter.rebuild(from: second, into: realm)

                expect(summary.folderCount) == 1
                expect(realm.objects(CPYFolder.self).count) == 1
                expect(realm.objects(CPYFolder.self).first?.title) == "New"
                expect(realm.objects(CPYSnippet.self).count) == 1
            }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/AppleNotesImporterSpec`
Expected: FAIL — `AppleNotesImporter` unresolved.

- [ ] **Step 3: Write the implementation**

Create `Clipy/Sources/Snippets/AppleNotesImporter.swift`:

```swift
import Foundation
import RealmSwift

enum AppleNotesImporter {
    static let maxFolderDepth = 5

    /// Collapse folders deeper than `maxDepth`. `depth` is 1-based for the passed
    /// folder. When a subfolder would exceed the limit, it is dropped and every
    /// snippet in its (recursively collapsed) subtree is lifted into `folder`.
    static func flatten(_ folder: NotesFolderNode, maxDepth: Int = maxFolderDepth) -> NotesFolderNode {
        return flatten(folder, depth: 1, maxDepth: maxDepth)
    }

    private static func flatten(_ folder: NotesFolderNode, depth: Int, maxDepth: Int) -> NotesFolderNode {
        var snippets = folder.snippets
        var subfolders: [NotesFolderNode] = []
        for sub in folder.subfolders {
            if depth + 1 > maxDepth {
                snippets.append(contentsOf: collectSnippets(sub))
            } else {
                subfolders.append(flatten(sub, depth: depth + 1, maxDepth: maxDepth))
            }
        }
        return NotesFolderNode(title: folder.title, snippets: snippets, subfolders: subfolders)
    }

    private static func collectSnippets(_ folder: NotesFolderNode) -> [NotesSnippetNode] {
        var result = folder.snippets
        for sub in folder.subfolders {
            result.append(contentsOf: collectSnippets(sub))
        }
        return result
    }

    @discardableResult
    static func rebuild(from folder: NotesFolderNode, into realm: Realm) -> AppleNotesSummary {
        let capped = flatten(folder)
        var folderCount = 0
        var snippetCount = 0
        realm.transaction {
            realm.delete(realm.objects(CPYSnippet.self))
            realm.delete(realm.objects(CPYFolder.self))
            let counts = write(capped, parentIdentifier: "", index: 0, in: realm)
            folderCount = counts.folders
            snippetCount = counts.snippets
        }
        return AppleNotesSummary(folderCount: folderCount, snippetCount: snippetCount)
    }

    private static func write(_ node: NotesFolderNode, parentIdentifier: String, index: Int, in realm: Realm) -> (folders: Int, snippets: Int) {
        let folder = CPYFolder()
        folder.title = node.title
        folder.enable = true
        folder.index = index
        folder.parentIdentifier = parentIdentifier
        realm.add(folder)

        var folders = 1
        var snippets = 0
        var childIndex = 0

        for sub in node.subfolders {
            let counts = write(sub, parentIdentifier: folder.identifier, index: childIndex, in: realm)
            folders += counts.folders
            snippets += counts.snippets
            childIndex += 1
        }
        for snippetNode in node.snippets {
            let snippet = CPYSnippet()
            snippet.title = snippetNode.title
            snippet.content = snippetNode.content
            snippet.enable = true
            snippet.index = childIndex
            snippet.parentIdentifier = folder.identifier
            realm.add(snippet)
            snippets += 1
            childIndex += 1
        }
        return (folders, snippets)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/AppleNotesImporterSpec`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add Clipy/Sources/Snippets/AppleNotesImporter.swift ClipyTests/AppleNotesImporterSpec.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add apple notes importer with depth flattening"
```

---

### Task 6: AppleScript layer + output parser

**Files:**
- Create: `Clipy/Sources/Snippets/AppleNotesScripting.swift`
- Test: `ClipyTests/NotesOutputParserSpec.swift`

**Interfaces:**
- Consumes: `NotesFolderNode`, `NotesSnippetNode`, `AppleNotesError`, Foundation.
- Produces:
  - `protocol AppleNotesScripting: Sendable { func listFolderNames() throws -> [String]; func fetchFolder(named name: String) throws -> NotesFolderNode; func revealFolder(named name: String) throws }`
  - `enum NotesOutputParser { static func parseFolderNames(_ raw: String) -> [String]; static func parseNotes(_ raw: String, folderName: String) -> NotesFolderNode }`
  - `struct AppleScriptNotesScripting: AppleNotesScripting`

**Design note:** AppleScript's nested-folder access is unreliable across macOS versions, so the real fetch reads the notes **directly contained** in the chosen folder as a flat list (record-separator `\u{1D}`, field-separator `\u{1E}`). Subfolder discovery is best-effort and out of scope for the parser here (nesting is capped later by the importer regardless). The parser is the unit-tested surface; the `NSAppleScript` calls are exercised only at runtime.

- [ ] **Step 1: Write the failing parser test**

Create `ClipyTests/NotesOutputParserSpec.swift`:

```swift
import Quick
import Nimble
import Foundation
@testable import Clipy

class NotesOutputParserSpec: QuickSpec {
    override class func spec() {
        describe("parseFolderNames") {
            it("splits newline-delimited folder names and trims blanks") {
                let raw = "Notes\nSnippets\n\nWork\n"
                expect(NotesOutputParser.parseFolderNames(raw)) == ["Notes", "Snippets", "Work"]
            }
        }

        describe("parseNotes") {
            it("builds a folder node with title+content pairs") {
                let rs = "\u{1D}"
                let fs = "\u{1E}"
                let raw = "hello\(fs)Hello, world!\(rs)sig\(fs)Best,\nAnk"
                let node = NotesOutputParser.parseNotes(raw, folderName: "Snippets")
                expect(node.title) == "Snippets"
                expect(node.subfolders).to(beEmpty())
                expect(node.snippets.count) == 2
                expect(node.snippets[0]) == NotesSnippetNode(title: "hello", content: "Hello, world!")
                expect(node.snippets[1]) == NotesSnippetNode(title: "sig", content: "Best,\nAnk")
            }

            it("returns an empty folder for empty output") {
                let node = NotesOutputParser.parseNotes("", folderName: "Empty")
                expect(node.title) == "Empty"
                expect(node.snippets).to(beEmpty())
            }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/NotesOutputParserSpec`
Expected: FAIL — `NotesOutputParser` unresolved.

- [ ] **Step 3: Write the implementation**

Create `Clipy/Sources/Snippets/AppleNotesScripting.swift`:

```swift
import Foundation

protocol AppleNotesScripting: Sendable {
    func listFolderNames() throws -> [String]
    func fetchFolder(named name: String) throws -> NotesFolderNode
    func revealFolder(named name: String) throws
}

enum NotesOutputParser {
    private static let recordSeparator = "\u{1D}"
    private static let fieldSeparator = "\u{1E}"

    static func parseFolderNames(_ raw: String) -> [String] {
        return raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func parseNotes(_ raw: String, folderName: String) -> NotesFolderNode {
        let snippets: [NotesSnippetNode] = raw
            .components(separatedBy: recordSeparator)
            .filter { !$0.isEmpty }
            .map { record in
                let parts = record.components(separatedBy: fieldSeparator)
                let title = parts.first ?? ""
                let content = parts.count > 1 ? parts[1] : ""
                return NotesSnippetNode(title: title, content: content)
            }
        return NotesFolderNode(title: folderName, snippets: snippets, subfolders: [])
    }
}

struct AppleScriptNotesScripting: AppleNotesScripting {
    private static let recordSeparator = "\u{1D}"
    private static let fieldSeparator = "\u{1E}"

    func listFolderNames() throws -> [String] {
        let source = """
        tell application "Notes"
            set out to ""
            repeat with f in folders
                set out to out & (name of f) & linefeed
            end repeat
            return out
        end tell
        """
        return NotesOutputParser.parseFolderNames(try run(source))
    }

    func fetchFolder(named name: String) throws -> NotesFolderNode {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Notes"
            set out to ""
            set theFolder to first folder whose name is "\(escaped)"
            repeat with n in notes of theFolder
                set out to out & (name of n) & "\(Self.fieldSeparator)" & (plaintext of n) & "\(Self.recordSeparator)"
            end repeat
            return out
        end tell
        """
        return NotesOutputParser.parseNotes(try run(source), folderName: name)
    }

    func revealFolder(named name: String) throws {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Notes"
            activate
            show (first folder whose name is "\(escaped)")
        end tell
        """
        _ = try run(source)
    }

    private func run(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AppleNotesError.scriptFailed("could not compile script")
        }
        let descriptor = script.executeAndReturnError(&error)
        if let error = error {
            let number = error[NSAppleScript.errorNumber] as? Int
            // -1743 = not authorized to send Apple events; -600 = app not running.
            if number == -1743 { throw AppleNotesError.notAuthorized }
            if number == -600 { throw AppleNotesError.notesUnavailable }
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown AppleScript error"
            throw AppleNotesError.scriptFailed(message)
        }
        return descriptor.stringValue ?? ""
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/NotesOutputParserSpec`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add Clipy/Sources/Snippets/AppleNotesScripting.swift ClipyTests/NotesOutputParserSpec.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add apple notes applescript layer and parser"
```

---

### Task 7: AppleNotesService + Environment wiring

**Files:**
- Create: `Clipy/Sources/Services/AppleNotesService.swift`
- Modify: `Clipy/Sources/Environments/Environment.swift:18-52`
- Modify: `Clipy/Sources/Environments/AppEnvironment.swift:30-68`
- Test: `ClipyTests/AppleNotesServiceSpec.swift`

**Interfaces:**
- Consumes: `AppleNotesScripting`, `AppleNotesImporter`, `SnippetSourceStore`, `AppleNotesSnippetCache`, `NotesFolderNode`, `AppleNotesSummary`, `AppleNotesError`, RealmSwift.
- Produces:
  - `final class AppleNotesService`
    - `init(scripting: AppleNotesScripting = AppleScriptNotesScripting())`
    - `func availableFolders() -> Result<[String], AppleNotesError>`
    - `func refresh(into realm: Realm) -> Result<AppleNotesSummary, AppleNotesError>` — used by tests with an injected realm.
    - `func refresh() -> Result<AppleNotesSummary, AppleNotesError>` — production path; opens the cache realm and delegates.
    - `func revealSelectedFolder()`
- Environment gains `let appleNotesService: AppleNotesService` (default `AppleNotesService()`), threaded through both initializers and `AppEnvironment.replaceCurrent(...)`.

- [ ] **Step 1: Write the failing test**

Create `ClipyTests/AppleNotesServiceSpec.swift`:

```swift
import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

private struct StubScripting: AppleNotesScripting {
    let folders: [String]
    let folder: NotesFolderNode
    let error: AppleNotesError?

    func listFolderNames() throws -> [String] {
        if let error = error { throw error }
        return folders
    }
    func fetchFolder(named name: String) throws -> NotesFolderNode {
        if let error = error { throw error }
        return folder
    }
    func revealFolder(named name: String) throws {
        if let error = error { throw error }
    }
}

class AppleNotesServiceSpec: QuickSpec {
    override class func spec() {
        var realm: Realm!

        beforeEach {
            var config = Realm.Configuration.defaultConfiguration
            config.inMemoryIdentifier = NSUUID().uuidString
            realm = try! Realm(configuration: config)
            let defaults = UserDefaults(suiteName: "AppleNotesServiceSpec-\(NSUUID().uuidString)")!
            AppEnvironment.replaceCurrent(environment: Environment(defaults: defaults))
            SnippetSourceStore.appleNotesFolder = "Snippets"
        }

        it("lists folders from scripting") {
            let scripting = StubScripting(folders: ["A", "B"],
                                          folder: NotesFolderNode(title: "Snippets", snippets: [], subfolders: []),
                                          error: nil)
            let service = AppleNotesService(scripting: scripting)
            expect(service.availableFolders()) == .success(["A", "B"])
        }

        it("refreshes the cache from the selected folder") {
            let folder = NotesFolderNode(title: "Snippets",
                                         snippets: [NotesSnippetNode(title: "x", content: "X")],
                                         subfolders: [])
            let service = AppleNotesService(scripting: StubScripting(folders: [], folder: folder, error: nil))
            let result = service.refresh(into: realm)
            expect(result) == .success(AppleNotesSummary(folderCount: 1, snippetCount: 1))
            expect(realm.objects(CPYSnippet.self).count) == 1
        }

        it("leaves the cache intact on error") {
            let good = NotesFolderNode(title: "Snippets",
                                       snippets: [NotesSnippetNode(title: "x", content: "X")],
                                       subfolders: [])
            _ = AppleNotesService(scripting: StubScripting(folders: [], folder: good, error: nil)).refresh(into: realm)
            let failing = AppleNotesService(scripting: StubScripting(folders: [], folder: good, error: .notAuthorized))
            let result = failing.refresh(into: realm)
            expect(result) == .failure(.notAuthorized)
            expect(realm.objects(CPYSnippet.self).count) == 1
        }

        it("fails when no folder is selected") {
            SnippetSourceStore.appleNotesFolder = nil
            let service = AppleNotesService(scripting: StubScripting(folders: [], folder: NotesFolderNode(title: "", snippets: [], subfolders: []), error: nil))
            expect(service.refresh(into: realm)) == .failure(.folderNotFound)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/AppleNotesServiceSpec`
Expected: FAIL — `AppleNotesService` unresolved.

- [ ] **Step 3: Write the service**

Create `Clipy/Sources/Services/AppleNotesService.swift`:

```swift
import Foundation
import RealmSwift

final class AppleNotesService {
    private let scripting: AppleNotesScripting

    init(scripting: AppleNotesScripting = AppleScriptNotesScripting()) {
        self.scripting = scripting
    }

    func availableFolders() -> Result<[String], AppleNotesError> {
        do {
            return .success(try scripting.listFolderNames())
        } catch let error as AppleNotesError {
            return .failure(error)
        } catch {
            return .failure(.scriptFailed(error.localizedDescription))
        }
    }

    func refresh(into realm: Realm) -> Result<AppleNotesSummary, AppleNotesError> {
        guard let folderName = SnippetSourceStore.appleNotesFolder else {
            return .failure(.folderNotFound)
        }
        do {
            let folder = try scripting.fetchFolder(named: folderName)
            let summary = AppleNotesImporter.rebuild(from: folder, into: realm)
            return .success(summary)
        } catch let error as AppleNotesError {
            return .failure(error)
        } catch {
            return .failure(.scriptFailed(error.localizedDescription))
        }
    }

    func refresh() -> Result<AppleNotesSummary, AppleNotesError> {
        guard let realm = AppleNotesSnippetCache.realm() else {
            return .failure(.scriptFailed("cache unavailable"))
        }
        return refresh(into: realm)
    }

    func revealSelectedFolder() {
        guard let folderName = SnippetSourceStore.appleNotesFolder else { return }
        try? scripting.revealFolder(named: folderName)
    }
}
```

- [ ] **Step 4: Wire into Environment**

In `Clipy/Sources/Environments/Environment.swift`, add the property after line 26 (`inputSourceService`):

```swift
    let inputSourceService: InputSourceService
    let appleNotesService: AppleNotesService
```

Add the init parameter after line 39 and the assignment after line 50:

```swift
         inputSourceService: InputSourceService = InputSourceService(),
         appleNotesService: AppleNotesService = AppleNotesService(),
         defaults: UserDefaults = .standard) {
```
```swift
        self.inputSourceService = inputSourceService
        self.appleNotesService = appleNotesService
        self.defaults = defaults
```

- [ ] **Step 5: Wire into AppEnvironment.replaceCurrent**

In `Clipy/Sources/Environments/AppEnvironment.swift`, add to the `replaceCurrent(...)` convenience (parameter list after line 38, and the `Environment(...)` call after line 48):

```swift
                               inputSourceService: InputSourceService = current.inputSourceService,
                               appleNotesService: AppleNotesService = current.appleNotesService,
                               defaults: UserDefaults = current.defaults) {
```
```swift
                                                inputSourceService: inputSourceService,
                                                appleNotesService: appleNotesService,
                                                defaults: defaults))
```

Also add `appleNotesService: current.appleNotesService,` to the `Environment(...)` returned by `fromStorage(...)` (after line 67).

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/AppleNotesServiceSpec`
Expected: PASS (4 examples).

- [ ] **Step 7: Commit**

```bash
git add Clipy/Sources/Services/AppleNotesService.swift Clipy/Sources/Environments/Environment.swift Clipy/Sources/Environments/AppEnvironment.swift ClipyTests/AppleNotesServiceSpec.swift Clipy.xcodeproj/project.pbxproj
git commit -m "add apple notes service and environment wiring"
```

---

### Task 8: Menu builder routing

**Files:**
- Modify: `Clipy/Sources/Managers/MenuManager.swift` (add `activeSnippetRealm()`, `rebuildSnippetSource()`; route `popUpSnippetFolder` at line 400)
- Modify: `Clipy/Sources/Managers/MenuManager+MenuBuilders.swift:355` (route `addSnippetItems`)
- Modify: `Clipy/Sources/AppDelegate.swift:165` (route `selectSnippetMenuItem`)
- Test: `ClipyTests/SnippetMenuRoutingSpec.swift`

**Interfaces:**
- Consumes: `SnippetSourceStore`, `AppleNotesSnippetCache`, `MenuManager.realm`.
- Produces:
  - `MenuManager.activeSnippetRealm() -> Realm?` — cache realm in Apple Notes mode, else the native `realm`.
  - `MenuManager.rebuildSnippetSource()` — recreates the clip menu on the main thread.

- [ ] **Step 1: Write the failing test**

Create `ClipyTests/SnippetMenuRoutingSpec.swift`:

```swift
import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class SnippetMenuRoutingSpec: QuickSpec {
    override class func spec() {
        beforeEach {
            let defaults = UserDefaults(suiteName: "SnippetMenuRoutingSpec-\(NSUUID().uuidString)")!
            AppEnvironment.replaceCurrent(environment: Environment(defaults: defaults))
        }

        it("returns the native realm in native mode") {
            SnippetSourceStore.current = .native
            let manager = MenuManager()
            expect(manager.activeSnippetRealm()?.configuration.fileURL)
                == manager.realm?.configuration.fileURL
        }

        it("returns the cache realm in apple notes mode") {
            SnippetSourceStore.current = .appleNotes
            let manager = MenuManager()
            let cacheURL = AppleNotesSnippetCache.configuration().fileURL
            expect(manager.activeSnippetRealm()?.configuration.fileURL) == cacheURL
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/SnippetMenuRoutingSpec`
Expected: FAIL — `activeSnippetRealm` unresolved.

- [ ] **Step 3: Add the routing helpers to MenuManager**

In `Clipy/Sources/Managers/MenuManager.swift`, inside the `MenuManager` class body (near the `realm` property at line 47), add:

```swift
    func activeSnippetRealm() -> Realm? {
        if SnippetSourceStore.current == .appleNotes {
            return AppleNotesSnippetCache.realm()
        }
        return realm
    }

    func rebuildSnippetSource() {
        DispatchQueue.main.async { [weak self] in
            self?.createClipMenu()
        }
    }
```

- [ ] **Step 4: Route `addSnippetItems`**

In `Clipy/Sources/Managers/MenuManager+MenuBuilders.swift`, change line 355 from:

```swift
        guard let realm = realm else { return }
```
to:
```swift
        guard let realm = activeSnippetRealm() else { return }
```

- [ ] **Step 5: Route `popUpSnippetFolder`**

In `Clipy/Sources/Managers/MenuManager.swift`, change line 400 from:

```swift
        if let realm = realm {
```
to:
```swift
        if let realm = activeSnippetRealm() {
```

- [ ] **Step 6: Route the paste lookup**

In `Clipy/Sources/AppDelegate.swift`, change line 165 from:

```swift
        guard let realm = Realm.safeInstance() else { return }
```
to:
```swift
        guard let realm = AppEnvironment.current.menuManager.activeSnippetRealm() else { return }
```

- [ ] **Step 7: Run test + full build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test -only-testing:ClipyTests/SnippetMenuRoutingSpec`
Expected: PASS (2 examples).
Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add Clipy/Sources/Managers/MenuManager.swift Clipy/Sources/Managers/MenuManager+MenuBuilders.swift Clipy/Sources/AppDelegate.swift ClipyTests/SnippetMenuRoutingSpec.swift
git commit -m "route snippet menu and paste through active snippet realm"
```

---

### Task 9: Refresh on launch + rebuild menu after refresh

**Files:**
- Modify: `Clipy/Sources/AppDelegate.swift` (in `applicationDidFinishLaunching`, after the existing `hotKeyService.setupDefaultHotKeys()` / bootstrap block)

**Interfaces:**
- Consumes: `SnippetSourceStore`, `AppEnvironment.current.appleNotesService`, `MenuManager.rebuildSnippetSource()`.
- Produces: a private `refreshAppleNotesSnippetsIfNeeded()` helper on `AppDelegate`.

- [ ] **Step 1: Add the launch refresh helper**

In `Clipy/Sources/AppDelegate.swift`, add a private method (place it near the other bootstrap helpers in the file):

```swift
    private func refreshAppleNotesSnippetsIfNeeded() {
        guard SnippetSourceStore.current == .appleNotes else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = AppEnvironment.current.appleNotesService.refresh()
            AppEnvironment.current.menuManager.rebuildSnippetSource()
        }
    }
```

- [ ] **Step 2: Call it from `applicationDidFinishLaunching`**

In `applicationDidFinishLaunching(_:)`, after the existing App Launcher / input source bootstrap calls, add:

```swift
        refreshAppleNotesSnippetsIfNeeded()
```

- [ ] **Step 3: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Clipy/Sources/AppDelegate.swift
git commit -m "refresh apple notes snippets on launch"
```

---

### Task 10: Snippets preferences pane (programmatic UI, no XIB)

**Files:**
- Create: `Clipy/Sources/Preferences/Panels/CPYSnippetPreferenceViewController.swift`
- Modify: `Clipy/Sources/Preferences/CPYPreferencesWindowController.swift`

**Approach:** No XIB. The pane view controller builds its view in `loadView()` with an `NSStackView`. It is registered as an 8th tab that the window controller creates **programmatically** in `windowDidLoad()` (a button + image + label appended to the existing `toolBar` view), so the preferences XIB is not edited. UI strings are plain Swift literals (no SwiftGen/L10n dependency).

**Interfaces:**
- Consumes: `SnippetSource`, `SnippetSourceStore`, `AppEnvironment.current.appleNotesService`, `AppEnvironment.current.menuManager.rebuildSnippetSource()`.
- Produces: `final class CPYSnippetPreferenceViewController: NSViewController` whose view is 480 wide (match the other panes' content width) and self-sizing in height. Actions are plain `@objc` methods wired via `target/action` in code (not `@IBAction`).

- [ ] **Step 1: Write the view controller (programmatic view)**

Create `Clipy/Sources/Preferences/Panels/CPYSnippetPreferenceViewController.swift`. Build the view in `loadView()` using an `NSStackView` (vertical, gravity-based) containing:
- a labeled `NSPopUpButton` "Snippet source" with items "Native" (tag 0) and "Apple Notes" (tag 1), target/action → `sourceChanged(_:)`;
- a labeled `NSPopUpButton` for folders → `folderSelected(_:)`;
- a horizontal row of `NSButton`s: "Reload folders" → `reloadFoldersTapped(_:)`, "Edit in Apple Notes" → `editInNotesTapped(_:)`, "Refresh snippets" → `refreshTapped(_:)`;
- a multiline wrapping `NSTextField` (label, `isEditable = false`, `isBezeled = false`, `drawsBackground = false`) as the status line.

Set `view.frame = NSRect(x: 0, y: 0, width: 480, height: 210)` (the window controller resizes to this frame; keep height reasonable). Keep references to the controls as private `let`/`var` stored properties (they are created in code, not outlets).

The behavior logic is identical to the original plan — reproduce these methods verbatim, with the controls referenced as your stored properties instead of outlets:

```swift
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
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AppEnvironment.current.appleNotesService.refresh()
            DispatchQueue.main.async {
                self.applyRefreshResult(result)
                AppEnvironment.current.menuManager.rebuildSnippetSource()
            }
        }
    }

    private func reloadFolders() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AppEnvironment.current.appleNotesService.availableFolders()
            DispatchQueue.main.async {
                switch result {
                case .success(let folders):
                    self.folderPopUp.removeAllItems()
                    self.folderPopUp.addItems(withTitles: folders)
                    if let selected = SnippetSourceStore.appleNotesFolder, folders.contains(selected) {
                        self.folderPopUp.selectItem(withTitle: selected)
                    } else {
                        SnippetSourceStore.appleNotesFolder = self.folderPopUp.titleOfSelectedItem
                    }
                case .failure(let error):
                    self.statusLabel.stringValue = self.describe(error)
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
```

In `viewDidLoad()` call: `sourceMatrix.selectItem(withTag: SnippetSourceStore.current.rawValue)`, then `reloadFolders()`, then `updateEnabledState()`.

Swift 6 note: all the `DispatchQueue.*.async` closures above capture `self` (an `NSViewController`, main-actor-ish but non-Sendable). If the compiler rejects `self` capture across the background queue, capture only the specific values needed and hop back to main for UI — but the pattern here dispatches static/singleton calls on the background queue and touches `self`'s UI only inside the nested `DispatchQueue.main.async`, which is the safe shape. Adjust minimally if the compiler complains, preserving behavior.

- [ ] **Step 2: Register the pane + create the toolbar tab programmatically**

In `CPYPreferencesWindowController.swift`:
- Append to the `viewController` array: `CPYSnippetPreferenceViewController()` (index 7). (It builds its own view; no nib name needed.)
- Add three private stored properties for the new tab's chrome, created in code: `snippetButton: NSButton`, `snippetImageView: NSImageView`, `snippetTextField: NSTextField` (optional or lazily built).
- In `windowDidLoad()`, after the existing tab setup, call a new `installSnippetTab()` that: creates the button/image/label, positions them inside `toolBar` to the right of the existing Beta tab (mirror the geometry/spacing of an existing tab — read the frames of the existing toolbar buttons at runtime to compute the next x-offset), sets `snippetButton.tag = 7`, `target = self`, `action = #selector(toolBarItemTapped(_:))`, `snippetButton.sendAction(on: .leftMouseDown)`, and labels it "Snippets".
- Extend `resetImages()` and `selectedTab(_:)` to handle the snippet tab (guard the programmatic views for nil): in `resetImages()` set `snippetTextField.textColor = .secondaryLabelColor` and a neutral image; add `case 7:` in `selectedTab(_:)` that highlights `snippetTextField` with `.controlAccentColor`. Reuse an existing pref icon asset (e.g. `Asset.prefMenu` / `Asset.prefMenuOn`) since no dedicated Snippets icon exists.

If precise toolbar geometry proves fragile, an acceptable fallback is to widen the window's toolbar area and lay the new button out with the same width/spacing as the existing buttons; the goal is a clickable 8th tab that switches to the Snippets pane via the existing `switchView(_:)`.

- [ ] **Step 3: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification (user-run)**

Build Release and run:
```
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  CONFIGURATION_BUILD_DIR=/Users/ank/dev/clipy/build/Release \
  CODE_SIGN_IDENTITY="Clipy Dev" CODE_SIGN_STYLE=Manual build
pkill -x Clipy; open /Users/ank/dev/clipy/build/Release/Clipy.app
```
Open Preferences → the new **Snippets** tab. Switching to Apple Notes enables the folder dropdown, which lists Notes folders (grant Automation permission when prompted). Selecting a folder + Refresh shows a count, and the snippet menu shows those notes. "Edit in Apple Notes" opens Notes on the folder.

- [ ] **Step 5: Commit**

```bash
git add Clipy/Sources/Preferences Clipy.xcodeproj/project.pbxproj
git commit -m "add snippets preferences pane for apple notes source"
```

---

### Task 11: Read-only editor in Apple Notes mode (programmatic banner, no XIB)

**Files:**
- Modify: `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift`

**Approach:** No XIB. In Apple Notes mode, point the editor's outline at the active snippet realm, disable the existing mutation controls (they are already IBOutlets on the controller), and add a banner **programmatically** as a subview of the window's content view.

**Interfaces:**
- Consumes: `SnippetSourceStore`, `AppEnvironment.current.appleNotesService`, `AppEnvironment.current.menuManager.activeSnippetRealm()`.
- Produces: a private `applyAppleNotesReadOnlyModeIfNeeded()` invoked at the end of `windowDidLoad()`.

- [ ] **Step 1: Point the editor's outline at the active source**

Find where this controller reads snippets for display (its outline data source uses a Realm — currently `Realm.safeInstance()` or a stored `realm`). Change the DISPLAY read path to `AppEnvironment.current.menuManager.activeSnippetRealm()` so the editor shows the Notes cache in Apple Notes mode. Report the exact property/method you changed. (Do not alter the native editing/mutation code paths — they are disabled below.)

- [ ] **Step 2: Add the read-only guard + programmatic banner**

Read the controller to find the real outlet names for the add/delete/import/change-status buttons and the content text view. Then add:

```swift
    private func applyAppleNotesReadOnlyModeIfNeeded() {
        guard SnippetSourceStore.current == .appleNotes else { return }

        // Disable every mutation control (use the real outlet names in this controller).
        // e.g. addSnippetButton, addFolderButton, deleteButton, changeStatusButton,
        //      importSnippetButton, and the content NSTextView's isEditable.
        // ... set each .isEnabled = false / textView.isEditable = false ...

        installManagedByNotesBanner()
    }

    private func installManagedByNotesBanner() {
        guard let contentView = window?.contentView else { return }
        let banner = NSTextField(labelWithString: "Managed by Apple Notes — edit in Apple Notes")
        let button = NSButton(title: "Edit in Apple Notes", target: self, action: #selector(editInAppleNotesTapped))
        banner.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(banner)
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            button.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: banner.trailingAnchor, constant: 12)
        ])
    }

    @objc private func editInAppleNotesTapped() {
        DispatchQueue.global(qos: .userInitiated).async {
            AppEnvironment.current.appleNotesService.revealSelectedFolder()
        }
    }
```

Call `applyAppleNotesReadOnlyModeIfNeeded()` at the end of `windowDidLoad()`. Adjust the banner placement constants if it overlaps existing content — the goal is a visible, non-overlapping banner with a working button.

- [ ] **Step 3: Build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification (user-run)**

With source = Apple Notes, open "Edit Snippets": the tree shows the Notes cache, add/delete/edit controls are disabled, and the banner + "Edit in Apple Notes" button are visible. Switch back to Native: full editing returns with all original snippets intact.

- [ ] **Step 5: Commit**

```bash
git add Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift
git commit -m "make snippet editor read-only in apple notes mode"
```

---

### Task 12: Full regression build + test

- [ ] **Step 1: Run the whole suite**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy test`
Expected: all specs pass, including the existing `SnippetXmlRoundTripSpec` (native path unaffected).

- [ ] **Step 2: Full build**

Run: `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke test (both modes)**

Native mode: snippets menu + editor behave exactly as before. Apple Notes mode: menu reflects the chosen folder, paste inserts the note's full text (including first line), losing Notes access still shows the last cached snippets.

---

## Self-Review Notes

- **Spec coverage:** Preferences section (Task 1, 10) · read-only mode (Task 11) · cache+refresh (Tasks 4, 5, 9) · dropdown folder pick (Task 10) · AppleScript access (Task 6) · dedicated cache Realm (Task 4) · title/content-with-first-line mapping (Tasks 5, 6) · last-cache-on-error (Tasks 5, 7) · menu routing + disabled folder hotkeys (Task 8) · Edit in Apple Notes button (Tasks 6, 10, 11). All spec sections map to tasks.
- **Placeholders:** UI/XIB steps (Tasks 10–11) are declarative by necessity (Interface Builder), but every associated Swift file is complete code; the XIB steps list exact outlets/actions and a build+manual verification.
- **Type consistency:** `NotesFolderNode`/`NotesSnippetNode`/`AppleNotesSummary`/`AppleNotesError` defined in Task 3 and used verbatim in Tasks 5–7 & 10. `activeSnippetRealm()` (Task 8) consumed in Tasks 8–11. `SnippetSourceStore` (Task 2) consumed throughout.
