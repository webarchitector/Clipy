# App Launcher Port from Selector — Design

**Date:** 2026-05-06
**Status:** awaiting user review

## Goal

Port the AppLauncher feature from `/Users/ank/dev/selector` into Clipy so that a single resident process — Clipy — handles both clipboard management and a global ⌘Space launcher panel for apps, math, and currency. After the port the user removes `/Applications/Selector.app` entirely; only one process holds the ⌘Space hotkey.

## Background

Selector currently embeds a launcher (`AppLauncher` in `selector/ShortcutCellView.swift`) bound to a Carbon hotkey. The launcher does three things in one panel:

- **Apps (A)** — global hotkey opens an `NSPanel` with a search field and table view. Filter matches case-insensitively against three indexes per app: original Latin name, Russian-PC-layout transliteration, lowercase Latin variant. Running apps appear at top with a green `●` dot. Apps in subfolders (`/Applications/Utilities/`, `/Applications/Setapp/`, …) resolve via a recursive walk.
- **Math (B)** — query containing `=` is normalized (`^` → `**`, `sqrt(x)` → `(x)**0.5`) and evaluated by `NSExpression`. Result row + "expression = result" row are offered for copy-on-Enter.
- **Currency (C)** — query like `15 usd thb=` parsed by regex; rates pulled from a per-base TSV cache under `~/.local/share/app-launcher/var/rates/`. If stale (>4h) or missing, fetches `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/<base>.json` in the background.

Cache files (`apps.txt`, `rates/*.tsv`) live under `~/.local/share/app-launcher/var/` by design — shared with a separate bash CLI `a` and (during transition) with the still-installed Selector.

Recent selector commits relevant to the port:
- `48eb308` invalidate cache when /Applications mtime changes
- `7237edc` async rebuild with auto-refresh of visible panel
- `a7e401f` Cyrillic uppercase filter via `q.lowercased()`
- `64215ff` recursive walk for nested .app bundles
- `2990604` single-source-of-truth `appSourceRoots`

## Scope

**In scope:**
- Verbatim port of A + B + C into Clipy. Behaviour identical to current selector.
- Five new Swift files under `Clipy/Sources/AppLauncher/`.
- One narrow exception in `NetworkIsolation` (AppDelegate.swift) for `cdn.jsdelivr.net`.
- Hotkey wiring via Magnet (Clipy's existing global-hotkey lib) with a row added to the existing shortcuts preference XIB.
- Quick/Nimble specs for pure-logic units (filter, math, currency parsing).
- Build verified per `AGENTS.md`:
  ```
  xcodebuild -workspace /Users/ank/dev/clipy/Clipy.xcworkspace \
    -scheme Clipy -configuration Release \
    -derivedDataPath /Users/ank/dev/clipy/build/DerivedData \
    CODE_SIGNING_ALLOWED=NO build
  ```

**Out of scope (this spec):**
- Removing AppLauncher from selector. Selector compiles unchanged. User decommissions `/Applications/Selector.app` post-deploy. Optional follow-up commit to strip the launcher from the selector repo can be a separate task.
- UI redesign of the launcher panel — verbatim port.
- New launcher features beyond what selector ships today.

## Architecture

Five new files in `Clipy/Sources/AppLauncher/` (one class per file, per Clipy convention):

### `AppLauncherService.swift`
Lifecycle/registration glue. Mirrors the style of `Clipy/Sources/Services/HotKeyService.swift`.

Public API:
- `static let shared`
- `func setup()` — called once from `AppDelegate.applicationDidFinishLaunching`. Pre-seeds default ⌘Space if `app-launcher-did-pre-seed` flag absent in `UserDefaults`. Reads stored `KeyCombo` from `Constants.HotKey.appLauncherKeyCombo`. Registers a `Magnet.HotKey` with identifier `"AppLauncherHotKey"`. Schedules `AppLauncher.shared.preload()` 200 ms later (matches selector's warm-up).
- `func change(keyCombo:)` — re-register when the user edits the shortcut from preferences.
- `@objc private func handleHotKey()` — calls `AppLauncher.shared.toggle()` on the main thread.

Logging via `NSLog` on registration failure (matches `HotKeyService`).

### `AppLauncher.swift`
Panel + filter + dispatch. Singleton `static let shared`.

Public surface:
- `func toggle()` — show panel if hidden, hide if visible.
- `func preload()` — builds panel + warms `AppIndex` + caches `runningApps` 200 ms after launch so first ⌘Space is as fast as subsequent ones.

Internal:
- `setupPanel()` — constructs `LauncherPanel` + `NSSearchField` + `NSTableView`, identical layout to selector.
- `show()` — sizes panel to visible screen, calls `AppIndex.shared.reloadIfNeeded()`, refreshes running apps from `NSWorkspace.runningApplications`, applies empty filter, makes panel key.
- `applyFilter(_ q: String)` — concatenates `Calculator.shared.items(for: q)` (math/currency) + `AppIndex.shared.match(query: q)` (apps, running first), populates table.
- `activateSelection()` — app → `AppIndex.shared.resolveURL(named:)` then `NSWorkspace.openApplication`; calc → `NSPasteboard.general` string copy; status → no-op.

Holds `runningApps: Set<String>`, `visibleItems: [LauncherItem]`, `lastQuery: String`. `LauncherItem` enum (app/calcCopyResult/calcCopyFull/status) defined here.

### `LauncherPanel.swift`
`NSPanel` subclass. Identical to selector except for the `⌘,` action: instead of `MainWindowController.shared.showAndActivate(self)` (selector), forwards to Clipy's existing preferences window. The exact selector call in clipy will be confirmed during implementation (likely `AppDelegate.openPreferenceWindow` or equivalent — clipy's preferences architecture differs from selector's).

Behaviour:
- `canBecomeKey == true`, `canBecomeMain == false`.
- `cancelOperation` (Esc) → `AppLauncher.shared.hide()`.
- `performKeyEquivalent` forwards `⌘C/V/X/A/Z` to first responder so the search field's standard editing keys work in an `LSUIElement` app without a visible Edit menu.
- `⌘,` → close + open Clipy preferences.

### `AppIndex.swift`
Cache + scan + match + URL resolution. Singleton.

Public surface:
- `static let shared`
- `func reloadIfNeeded()` — checks `appsFile` mtime, calls `appSourcesChanged` to detect `/Applications` changes since cache write, async rebuild via `buildIndexAsync` + auto-refresh in callback if panel visible. First-run blocks via `buildIndexSync`. 24h-stale falls back to `buildIndexAsync`.
- `func match(query:) -> [(name: String, running: Bool)]` — pre-lowered query, contains-match against `original.lowercased()`, `cyr`, `lat`. Running apps first.
- `func resolveURL(named:) -> URL?` — fast top-level path check; on miss, recursive walk in user roots up to depth 3.

Single source of truth:
```swift
private static let appSourceRoots: [(path: String, scanDepth: Int)] = [
    ("/Applications", 3),
    ("/System/Applications", 3),
    (NSHomeDirectory() + "/Applications", 3),
    ("/System/Library/CoreServices", 1)
]
```

Translit tables `cyrToLat` and derived `latToCyr` live here too.

Cache files written/read at `~/.local/share/app-launcher/var/apps.txt`. Path is intentionally OUTSIDE Clipy's bundle/sandbox container — bash CLI `a` and migrating Selector users share the file.

### `Calculator.swift`
Pure parsing/eval + currency fetching. Singleton.

Public surface:
- `static let shared`
- `func items(for query: String) -> [LauncherItem]` — `[]` when query lacks `=`, else math/currency rows.

Internal: `evaluateMath`, `parseCurrency`, `currencyItems`, `kickOffFetch`, `readRate`, `formatRate`. Verbatim from selector.

`URLSession.shared.dataTask` used directly. With the host whitelist below in place, requests succeed; without it, they fail immediately with `NSURLErrorDataNotAllowed` and the panel shows `"fetching <BASE> rates…"` indefinitely.

## Hotkey Integration

### `Constants.swift`
Add to existing `enum HotKey`:
```swift
static let appLauncherKeyCombo = "appLauncherKeyCombo"
```

### `HotKeyService.swift`
**Untouched.** `HotKeyService` continues to own only the three existing main/history/snippet hotkeys. The launcher's hotkey registration lives entirely in `AppLauncherService` to keep the new feature self-contained and the existing service untouched.

Pre-seed (default ⌘Space on first launch, gated by `app-launcher-did-pre-seed` flag) runs **once** in `AppLauncherService.setup()` — described in the `AppLauncherService.swift` section above. It is not duplicated in `HotKeyService`.

`AppLauncherService` is invoked from the same startup hook as `HotKeyService` (`AppDelegate.applicationDidFinishLaunching` or whichever specific entry point Clipy currently uses to bootstrap services — confirmed during implementation; both run sequentially on the main thread, no ordering constraint between them).

### `CPYShortcutsPreferenceViewController` (XIB + Swift)
Add a fourth row in the existing shortcuts table/stack with label `"App Launcher"` and a `KeyHolder.RecordView` bound to `Constants.HotKey.appLauncherKeyCombo`. Same plumbing pattern as the existing three rows.

## Network Isolation Exception

Modify `NetworkIsolation` in `Clipy/Sources/AppDelegate.swift`:

```swift
private enum NetworkIsolation {
    private static let blockedSchemes = Set(["ftp", "ftps", "http", "https", "ws", "wss"])

    /// App Launcher's currency feature is the only outbound network egress in
    /// the entire process. Adding a host to this set is the only sanctioned
    /// way to pierce the otherwise process-wide URLProtocol block.
    private static let allowedHosts: Set<String> = [
        "cdn.jsdelivr.net"
    ]

    static func configureProcess() { … unchanged … }

    static func shouldBlock(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        if let host = url?.host?.lowercased(), allowedHosts.contains(host) {
            return false
        }
        return blockedSchemes.contains(scheme)
    }
}
```

The whitelist is one host. The only code that contacts it is `Calculator.kickOffFetch`. Other code paths remain blocked.

`AGENTS.md` rule "do not reintroduce general network access unless explicitly requested" — this is the explicit user request; the spec records the request. The narrow whitelist is intentionally not generic ("allow all") so the offline posture is preserved everywhere except the one launcher feature.

## Cache Paths

| Path | Format | Producer | Consumer |
|------|--------|----------|----------|
| `~/.local/share/app-launcher/var/apps.txt` | `<name>\t<cyr>\t<lat>` lines, `# v4` header | `AppIndex.buildIndexAsync` (Clipy + Selector) and bash CLI `a` | `AppIndex.match` (both) and CLI `a` (third party) |
| `~/.local/share/app-launcher/var/rates/<base>.tsv` | `<ccy>\t<rate>` lines | `Calculator.kickOffFetch` (Clipy only post-port) | `Calculator.readRate` |

Paths sit outside Clipy's app bundle and outside any sandbox container — by design for cross-tool sharing. This is intentional and explicit.

## Data Flow

```
⌘Space ──Magnet──▶ AppLauncherService.handleHotKey()
                         │
                         ▼
                   AppLauncher.shared.toggle()
                         │
                ┌────────┴────────┐
              hidden          visible
                │                │
                ▼                ▼
              show()           hide()
                │
   ┌────────────┼─────────────────┐
   ▼            ▼                 ▼
AppIndex     refresh         applyFilter("")
.reloadIf    runningApps          │
Needed                       ┌────┴─────┐
                             ▼          ▼
                    AppIndex.match  Calculator.items
                             │          │
                             └────┬─────┘
                                  ▼
                          tableView.reloadData

 Enter ──▶ activateSelection
            ├─ .app    → AppIndex.resolveURL → NSWorkspace.openApplication
            ├─ .calc*  → NSPasteboard.general.setString
            └─ .status → no-op
```

## Error Handling

| Failure | Behaviour |
|---------|-----------|
| Magnet `register` returns false | `NSLog`, no UI alert (matches `HotKeyService`) |
| URLSession dataTask fails (network whitelist hit, server down, JSON malformed) | Silent. Panel keeps showing `"fetching <BASE> rates…"` until a successful fetch lands |
| `AppIndex.resolveURL` returns nil (app deleted between cache rebuild and click) | No-op activation. Next `show()` rebuilds index because `appSourcesChanged` fires from `/Applications` mtime change |
| `apps.txt` write fails (disk full, perms) | `try?` swallows. Stale data on next read; `appsLoadedMtime == nil` retry next cycle |
| `URLProtocol` block hits an unwhitelisted host (defensive: shouldn't happen) | Existing `NSURLErrorDataNotAllowed` path. Diagnosable in Console.app |

## Testing

Three new specs under `ClipyTests/AppLauncher/` (Quick/Nimble, no AppKit/Magnet deps):

### `AppIndexFilterSpec.swift`
- Pre-lowered query: `"term"` matches `original="Terminal"`.
- Cyrillic uppercase: `"ЕУКЬШТФД"` (Russian-layout uppercase for `terminal`) lowers to `"еукьштфд"` and matches Terminal's `cyr` index.
- Empty query: returns all apps in stable order, running first.
- Translit round-trip: `latToCyr["t"] == "е"`, `cyrToLat["е"] == "t"`, applied across a sample (`Mail`, `Terminal`, `Safari`).

### `CalculatorMathSpec.swift`
- `"1+2"` → `"3"`.
- `"(1+2)*3"` → `"9"`.
- `"sqrt(4)"` → `"2"`.
- `"2^10"` → `"1024"`.
- `"1/0"` → nil (NaN/Inf rejected).
- Empty / pure garbage → nil.

### `CalculatorCurrencySpec.swift`
- `parseCurrency("15 usd thb")` → `(15.0, "usd", "thb")`.
- `parseCurrency("15.5 USD THB")` → `(15.5, "usd", "thb")`.
- `parseCurrency("nonsense")` → nil.
- `formatRate` integer vs decimal formatting.

UI/Magnet code is verified manually after build:
- ⌘Space opens panel (cold and warm).
- `term` finds Terminal; `ьфшд` and `ЬФШД` find Mail.
- `(1+2)*3=` shows two calc rows.
- `15 usd thb=` shows `"fetching…"` first time, then result rows after fetch.
- `⌘,` inside panel closes panel + opens Clipy preferences.
- Preferences → Shortcuts tab → fourth row "App Launcher" recordable.
- Delete an app from `/Applications`; ⌘Space — entry gone within ≤200 ms (auto-refresh on async rebuild completion).

## Migration

Post-port deployment:
1. Build Clipy with the launcher.
2. Quit Selector if running (`pkill -x Selector`).
3. Replace `/Applications/Clipy.app` with the new build.
4. Quit and relaunch Clipy. Verify ⌘Space brings up the launcher.
5. Remove `/Applications/Selector.app`.
6. Remove Selector's launch-on-startup entry if any (System Settings → General → Login Items).

Migration order matters: a second `RegisterEventHotKey` on ⌘Space fails. Whichever process registers first wins; the other hotkey is silently dead.

## What's Not Touched

- Realm models, schema, migrations.
- RxSwift wiring, `MenuManager`, debounced rebuilds.
- Existing shortcuts ⌘⇧V / ⌃⌘V / ⌘⇧B and their preference rows.
- Vendored deps. No new pods/frameworks. Magnet, KeyHolder, Sauce already present.
- `Clipy/Generated/*` (SwiftGen output).
- Apple Silicon-only build flags, `Scripts/strip-non-arm64-slices.sh`.
- `NetworkIsolation` blocked-schemes set. The diff is exactly one new property `allowedHosts` plus one branch in `shouldBlock`.

## Risks / Open Questions

1. **Symbolichotkey 64 (Spotlight) collision**: macOS reserves ⌘Space for Spotlight by default. Magnet's `register()` returns false silently. Selector's existing user has already disabled the system shortcut; the migrating user is the same person with the same setup, so this is not a new failure mode introduced by the port. Documented in code comment, not surfaced in UI.
2. **`cdn.jsdelivr.net` whitelist breadth**: that host serves any npm package. The whitelist is a host check, not a path check. If future code in Clipy were to issue requests to that host for unrelated reasons, they would also pass the block. Acceptable: only `Calculator.kickOffFetch` uses URLSession in the entire codebase post-port; `grep -r URLSession Clipy/Sources/` will catch any future regression in a code review.
3. **UserDefaults concurrency**: writes from preferences XIB and `AppLauncherService` are atomic via `NSUserDefaults` itself. Same pattern as the three existing hotkeys. No new locking required.
4. **Preferences window selector**: `LauncherPanel`'s `⌘,` handler needs the right call to open Clipy's preferences. Selector's `MainWindowController.shared.showAndActivate(self)` does not exist in Clipy. Implementation plan resolves the exact selector against Clipy's preferences window flow (likely `AppDelegate.openPreferenceWindow` or an `NSWindowController` subclass for preferences).
