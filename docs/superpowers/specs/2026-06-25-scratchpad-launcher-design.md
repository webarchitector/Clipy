# Scratchpad in the App Launcher — Design

Date: 2026-06-25

## Goal

Add a lightweight "scratchpad" to the Cmd-Space app-launcher panel: a place to
quickly stash text from the clipboard, edit it, copy it back, and delete it.
Notes persist across app restarts.

Core user flow: copy something → create a scratch note from the clipboard →
edit it → copy the edited text back to the clipboard → delete the note.

## Decisions (from brainstorming)

- **Entry point:** a single `📝 Scratchpad (N)` row shown as the **top item of
  the launcher results, only while the search field is empty**. It disappears as
  soon as the user types (normal launcher results take over).
- **Notes:** multiple notes, reached through that one entry point (a dedicated
  list, not scattered into the main launcher results).
- **Editing:** inline inside the Cmd-Space panel (no extra window). The panel
  morphs into a multi-line editor and back.
- **Storage:** a new Realm model `CPYScratchNote` (consistent with `CPYClip` /
  `CPYSnippet`). Adding a new Realm object class is additive — no manual
  migration / schema-version bump needed.

## Components (isolation)

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| `CPYScratchNote` (Realm model) | Persisted note: `identifier` (PK, UUID), `content: String`, `createdAt: Date`, `updatedAt: Date` | RealmSwift |
| `ScratchpadStore` | CRUD over Realm: `allNotes()`, `create(content:) -> id`, `update(id:content:)`, `delete(id:)`. No-ops / `[]` when `Realm.safeInstance()` is nil | RealmSwift |
| `ScratchTitle` (pure helper) | Derive a display title from content (first non-empty line, trimmed/truncated; `"New note"`/localized fallback when empty) | — |
| `ScratchpadController` | Owns the scratchpad UI (notes list + inline editor) hosted inside the launcher panel; talks to `ScratchpadStore`; debounced autosave | AppKit, `ScratchpadStore`, `ScratchTitle` |
| `AppLauncher` (existing) | Adds `LauncherItem.scratchpad`, prepends it when query is empty, and hands the panel over to `ScratchpadController` when selected | `ScratchpadController` |

Title is **derived**, never stored.

## Panel states

```
root  ──(select 📝 Scratchpad)──▶  list  ──(select a note / "New from clipboard")──▶  editor
  ◀──────────────(Esc)───────────────┘            ◀──────────(Esc)──────────────────┘
```

`AppLauncher` tracks the current mode. `ScratchpadController` renders `list` and
`editor` by swapping the panel's content; on returning to `root`, the normal
launcher table is restored.

### `list` mode
- Search field becomes a **filter over notes** (matches title + content,
  case/diacritic-insensitive).
- Rows: a pinned top row `➕ New from clipboard`, then notes sorted by
  `updatedAt` descending (title + short preview / relative date).
- `↑/↓` move selection; `Enter` opens the selected note (or runs "New from
  clipboard" on that row); mouse click opens.
- `Esc`: if the filter is non-empty, clear it; otherwise return to `root`.
- `⌘C`: copy the selected note's full text to the clipboard and hide the panel
  (grab a note without opening it).
- `⌘⌫`: delete the selected note.
- "New from clipboard" creates a note pre-filled with the current clipboard
  string (empty note if the clipboard has no string) and opens the editor.

### `editor` mode
- Search field is hidden; panel content is a scrollable multi-line `NSTextView`
  that grows with content up to a max height, then scrolls.
- Autosave: debounced (~400 ms) `update(id:content:)`, plus a final save when
  leaving the editor.
- `Esc`: save and return to `list`.
- `⌘Enter`: copy the current text to the clipboard and hide the panel (the
  "copy back to buffer" step). **The note is kept** (non-destructive default;
  delete is a separate action). A "copy and delete" variant can be added later
  if desired.
- `⌘⌫`: delete the note and return to `list`.

## Data flow

1. Panel opens (`root`), query empty → `AppLauncher` prepends
   `LauncherItem.scratchpad` with `ScratchpadStore.allNotes().count`.
2. Select it → `AppLauncher` enters scratchpad mode and asks
   `ScratchpadController` to show `list` (fed by `allNotes()`).
3. "New from clipboard" → `create(content: <clipboard string>)` → open `editor`
   on the new id.
4. Editing → debounced `update(id:content:)`; `updatedAt` bumped on each write.
5. `⌘Enter` → write clipboard, hide panel. `⌘⌫` → `delete(id:)`.

## Error handling / Swift 6

- `Realm.safeInstance()` nil → `allNotes()` returns `[]`, mutations are no-ops;
  the scratchpad row still appears (shows `(0)`) and "New from clipboard" simply
  fails to persist rather than crashing.
- Empty clipboard → empty note.
- UI is main-actor; Realm accessed on the main thread, as elsewhere in the app.
  `AppLauncher` is already `@unchecked Sendable`; `ScratchpadController` is
  main-actor and holds no cross-isolation shared state.

## Testing

- `ScratchpadStore` CRUD against an isolated in-memory Realm (create → list
  order by `updatedAt` → update bumps order → delete).
- `ScratchTitle` pure-function cases: empty, leading blank lines, single line,
  multi-line, very long line (truncation), whitespace-only.
- Launcher prepend logic: empty query yields `.scratchpad` as the first item;
  non-empty query does not.

UI interactions (mode transitions, key handling) are covered by manual
verification — they need a live panel and event loop.

## Out of scope (YAGNI)

Tags, folders, rich text, sync, sharing with clipboard history, multi-select.
