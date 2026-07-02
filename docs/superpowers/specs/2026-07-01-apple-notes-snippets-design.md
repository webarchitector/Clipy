# Apple Notes as a Snippet Source — Design

Date: 2026-07-01
Status: Approved (design), pending implementation plan

## Goal

Let the user choose, in Preferences, where snippets come from:

- **Native** — current behavior (snippets stored in the app's Realm, edited in the
  snippet editor window).
- **Apple Notes** — snippets are read (read-only) from a chosen Apple Notes folder.
  Its subfolders map to snippet subfolders and its notes map to snippets. Editing
  happens inside Apple Notes; Clipy re-reads on demand.

## Key Decisions

- **Read-only** in Apple Notes mode. Clipy never writes back to Notes. Editing is done
  in Apple Notes itself.
- **Cache + manual refresh.** Notes are imported into a local cache and the snippet menu
  is built from the cache (instant). The cache is rebuilt on: app start (when the mode is
  Apple Notes), the **Refresh snippets** button, and when the selected folder changes.
- **Folder chosen from a dropdown**, populated via AppleScript enumeration of Notes
  folders (with a re-list button).
- **Access method: AppleScript** (`NSAppleScript` / `osascript`). Direct reads of
  `NoteStore.sqlite` are rejected (encrypted, gzipped protobuf, Full Disk Access,
  fragile). AppleScript requires a one-time Automation permission (Apple Events → Notes).
- **Storage: dedicated cache Realm file** (`apple-notes-snippets.realm`), separate
  `Realm.Configuration`, using the same `CPYFolder` / `CPYSnippet` schema. The native
  snippet Realm is never touched by this feature.
- **Snippet mapping:** title = note name; content = full note plain text **including the
  first line**. Rich formatting is stripped (snippets are plain text).
- **On access loss** (permission revoked / Notes unavailable / folder missing): keep and
  show the **last successful cache**. The cache is overwritten only on a successful fetch.

## Architecture

### 1. Preferences — Snippets section

Add a **Snippets** section (in the existing General pane to avoid a whole new XIB pane;
a dedicated pane is an acceptable alternative if preferred during implementation).

Controls:

- Mode selector: **Native** / **Apple Notes**.
- When Apple Notes is selected, reveal:
  - **Apple Notes folder** dropdown (+ button to re-list folders).
  - **Edit in Apple Notes** — opens Notes.app focused on the selected folder.
  - **Refresh snippets** — re-reads the folder's notes into the cache.
  - Status line: "N folders, M snippets, updated HH:MM" or an access error with a hint to
    grant permission in System Settings.

UserDefaults keys:

- `kCPYSnippetSource` — Int (0 = native, 1 = apple notes).
- `kCPYAppleNotesFolder` — selected folder identifier/name.

Registered with defaults in `CPYUtilities.registerUserDefaultKeys()` (default source = native).

### 2. Apple Notes access layer

New `AppleNotesService` (registered in `AppEnvironment`, behind a protocol so it is
mockable in tests):

- `listFolders() -> [NotesFolder]` — enumerate folders (name + nesting when available) for
  the dropdown.
- `fetchTree(folderName:) -> NotesNode` — recursively read the chosen folder: subfolders →
  folder nodes, notes → snippet nodes (`title` = note name, `content` = plain text body).
- `revealFolder(folderName:)` — open Notes.app on the folder (Edit button).

Implementation notes:

- AppleScript via `NSAppleScript` / `osascript`, run **off the main thread**, with a
  timeout. On denied Automation permission or unreachable Notes, return a typed error
  surfaced in the Preferences status line.
- **Nesting caveat:** Notes' AppleScript exposes nested folders inconsistently across macOS
  versions. Read what is available; cap depth to the existing tree limit (max 5). Extra
  depth is flattened under the parent.

`NotesNode` and `NotesFolder` are plain Sendable value types (safe to pass across threads).

### 3. Cache + import (separate Realm)

- Cache Realm: `apple-notes-snippets.realm` (own `Realm.Configuration`, own file). Same
  `CPYFolder` / `CPYSnippet` schema.
- `AppleNotesImporter.rebuild(from tree:)` — in a single transaction, wipe the cache Realm
  and write the fresh tree (`title` / `content` / `index` / `parentIdentifier`,
  `enable = true`). Idempotent, no migrations — pure rebuild.
- Rebuild triggers: Refresh button, app start (when mode = Apple Notes), folder change.
- AppleScript reads happen in the background; the cache-Realm write happens on its own
  thread (Realm thread-confinement + Swift 6 Sendable — only the value snapshot crosses
  threads, never Realm objects).
- On fetch error, the cache is left intact (last successful state preserved).

### 4. Menu builder routing

- Helper `activeSnippetRealm()` — returns the cache Realm in Apple Notes mode, else
  `Realm.safeInstance()`.
- Snippet read sites switch to `activeSnippetRealm()`: `buildSnippetMenu`,
  `addSnippetItems`, `appendSnippetChildren`, `popUpSnippetFolder`
  (`MenuManager` / `MenuManager+MenuBuilders`). Types are unchanged, so the rest of the
  menu and paste flow is untouched.
- **Folder hotkeys** (`Constants.HotKey.folderKeyCombos`): disabled in Apple Notes mode —
  Notes folder identifiers are not stable across rebuilds. The global snippets-menu hotkey
  works as usual. (Documented limitation.)

### 5. Editor mode + source switching

- The snippet editor window (`CPYSnippetsEditorWindowController`) opens **read-only** in
  Apple Notes mode: it shows the cache tree; Add / Delete / Import / rename / text editing
  controls are disabled; a banner reads **"Managed by Apple Notes — edit in Apple Notes"**
  with a button duplicating **Edit in Apple Notes**.
- Native → Apple Notes: native Realm untouched; attempt to build the cache immediately (if a
  folder is chosen and access granted). Menu starts reading from the cache.
- Apple Notes → Native: cache is left as-is (rebuilt next time the mode is entered); menu and
  editor read the native Realm again with all prior snippets intact — nothing is lost.

### 6. Errors, edge cases, tests

- No Automation permission / Notes unavailable / folder missing → keep showing the last
  successful cache; Preferences status line shows a clear error + a hint to grant access in
  System Settings.
- Empty folder → empty menu, no crashes.
- Tests:
  - Round-trip `NotesNode` → cache Realm → menu build (modeled on
    `SnippetXmlRoundTripSpec`).
  - Note → snippet mapping (title/content, formatting stripped, first line included).
  - Depth cap > 5 (flattening).
  - AppleScript layer behind a protocol → mocked; tests never touch the real Notes app.

## Out of Scope

- Writing back to Apple Notes (two-way sync).
- Preserving rich text / attachments from notes.
- Per-folder hotkeys while in Apple Notes mode.

## Touched Areas (indicative)

- `Clipy/Sources/Preferences/…` — Snippets section UI + wiring.
- `Clipy/Sources/Services/AppleNotesService.swift` (new) + `AppEnvironment` registration.
- `Clipy/Sources/Snippets/AppleNotesImporter.swift` (new) + cache `Realm.Configuration`.
- `Clipy/Sources/Managers/MenuManager*.swift` — `activeSnippetRealm()` routing.
- `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController*.swift` — read-only mode + banner.
- `Clipy/Sources/Constants.swift`, `Clipy/Sources/Utility/CPYUtilities.swift` — new keys.
