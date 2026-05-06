# Project Index

_Last generated: 2026-05-06._

Navigation map for Clipy. Read this first to orient yourself; cross-reference `AGENTS.md` for editing rules and `CLAUDE.md` for build/commit rules. After any change that touches source layout, services, hotkey wiring, or external contracts, regenerate this file — see "Reindexing" at the bottom.

## Stack

- **Language/UI:** Swift, AppKit, XIBs (no SwiftUI).
- **Persistence:** Realm (`RealmSwift`).
- **Reactive:** RxSwift / RxCocoa.
- **Hotkeys:** Magnet (vendored).
- **Build:** Xcode workspace (`Clipy.xcworkspace`), arm64-only, no SPM/CocoaPods (all deps under `vendor/`).
- **Codegen:** SwiftGen → `Clipy/Generated/{LocalizedStrings,AssetsImages}.swift` (do not hand-edit).

## Top-Level Layout

```
Clipy/                   App source
├── Sources/             Swift code (~53 files)
├── Generated/           SwiftGen output — DO NOT EDIT
├── Resources/           Localized .strings, asset catalog
└── Xibs/                MainMenu.xib
ClipyTests/              Quick/Nimble specs
vendor/                  Vendored frameworks (Realm, RxSwift, Magnet, etc.)
docs/
├── INDEX.md             This file
└── archive/2026-05-app-launcher/   Design + plan docs for ported features
Scripts/strip-non-arm64-slices.sh   Post-build cleanup (arm64 only)
build/                   Local artifacts (gitignored)
```

## `Clipy/Sources/` Subdirectories

| Dir | Purpose |
|---|---|
| `AppLauncher/` (5 files) | ⌘Space launcher panel: apps, math, currency. Ported from Selector. |
| `InputSource/` (3 files) | Per-input-source layout-switch hotkeys. Ported from Selector. |
| `Services/` (8) | clip / paste / hotkey / cleanup / exclude / update / accessibility / thumbnails |
| `Models/` (6) | Realm: CPYClip, CPYClipData, CPYFolder, CPYSnippet, CPYAppInfo, CPYDraggedData |
| `Managers/` (2) | MenuManager, ClipboardHistoryWindowController |
| `Preferences/` | Preferences window + 5 panes (General, Type, Beta, Exclude, Shortcuts, Updates) |
| `Environments/` (2) | `AppEnvironment` (global container), `Environment` (struct) |
| `Extensions/` (11) | Realm, NSImage, NSMenuItem, NSPasteboard, etc. |
| `Enums/`, `Snippets/`, `Utility/`, `Views/` | small support |
| (root) | `AppDelegate.swift`, `Constants.swift` |

## Entry Points

- **`AppDelegate.applicationDidFinishLaunching(_:)`** bootstrap order:
  1. `AppEnvironment.replaceCurrent(...)` (load defaults), register UserDefaults.
  2. Login item sync, accessibility check.
  3. `clipService → dataCleanService → excludeAppService → pasteService → hotKeyService.setupDefaultHotKeys()`.
  4. `appLauncherService.setupHotKey()` — default ⌘Space, gated by `Constants.HotKey.appLauncherDidPreSeed`. Schedules a 200 ms `AppLauncher.shared.preload()`.
  5. `inputSourceService.setupHotKeys()` — iterates `InputSource.sources`, re-registers stored KeyCombos.
  6. `menuManager.setup()`.
- **`AppEnvironment.current` / `Environment`** — global service container (`Environments/`). Adding a new service requires updating `Environment.init`, `AppEnvironment.replaceCurrent(...)`, AND `AppEnvironment.fromStorage(...)`.

## External Contracts

- **`~/.local/share/app-launcher/var/apps.txt`** — shared with bash CLI `a` (and any pre-existing Selector install during transition). Format: `# v4` header, three tab-separated columns (original / Cyrillic translit / Latin translit). Read/written by `AppIndex`.
- **`~/.local/share/app-launcher/var/rates/<base>.tsv`** — FX rates, refreshed >4h via `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/<base>.json`. Used by `Calculator`.
- **`NetworkIsolation.allowedHosts`** in `AppDelegate.swift` (lines 23–50) — process-wide `URLProtocol` blocks all HTTP/HTTPS/FTP/WS schemes; only `cdn.jsdelivr.net` is whitelisted (for the FX-rates fetch above). Do not extend without explicit user request.
- **UserDefaults** for input-source hotkeys: per-source key `kCPYInputSource_<id-with-dots-replaced>`. Magnet hotkey identifiers: `"InputSource:<id>"`. Magnet holds target weakly, so `InputSourceService` retains `HotKeyTarget` via `objc_setAssociatedObject`.

## Ported Features (May 2026)

- **App Launcher** (`Clipy/Sources/AppLauncher/`, 5 files): NSPanel + NSSearchField + NSTableView (`AppLauncher.swift`, `LauncherPanel.swift`), index/cache/match (`AppIndex.swift`), math via `NSExpression` + currency via cdn.jsdelivr.net (`Calculator.swift`), Magnet wiring (`AppLauncherService.swift`). Singletons by design: `AppLauncher.shared`, `AppIndex.shared`, `Calculator.shared`.
- **Input Source switching** (`Clipy/Sources/InputSource/`, 3 files): `InputSource.swift` + `TISInputSource+Additions.swift` wrap Carbon TIS; `InputSourceService.swift` registers one Magnet hotkey per installed input source. Dedup at change time: claiming combo X for source A clears X from any source B that currently holds it (defaults + in-memory + RecordView).
- **Source-of-truth** (for future cherry-picks): `/Users/ank/dev/selector/selector/{ShortcutCellView,InputSourceManager}.swift`. Design + plan: `docs/archive/2026-05-app-launcher/`.
- Both ports start each file with `// swiftlint:disable identifier_name` to preserve drop-in portability with Selector's short-locals style.

## Preferences Shortcuts Pane (XIB Coupling)

`CPYShortcutsPreferenceViewController.xib` carries five static rows in fixed-frame layout:

- Inside container `uTq-IP-dYk` (top): App Launcher, Main, History, Snippets.
- Inside container `zgf-1z-HW3` (bottom): Clear History.

A "Layouts" section is appended programmatically by `appendInputSourcesSection()` after XIB load — parent view is resized, existing rows slide up via `flexibleMinY`. If the dynamic section would exceed ~360 px it wraps in `NSScrollView`. Adding a sixth static row means recomputing absolute y-positions (no auto-layout).

## Build & Tests

See `AGENTS.md` ("Build And Test") and `CLAUDE.md` ("Build") — authoritative.

## Reindexing

Regenerate this file when any of these change:

- Source tree under `Clipy/Sources/` (new dir, new module, removed module).
- Services on `AppEnvironment.Environment` (new property, new wiring site).
- Bootstrap order in `AppDelegate.applicationDidFinishLaunching`.
- External contracts (cache file format, allowed hosts, UserDefaults key naming).
- Ported-feature singletons or invariants.

To regenerate: ask Claude to "reindex project". The agent surveys `Clipy/Sources/`, `AppDelegate`, `Environment`, and external contracts, then rewrites this file. Update the date stamp at the top.
