# Project Index

For code navigation (classes, methods, call paths, references) use the
`codebase-memory-mcp` graph — project key `Users-ank-dev-clipy`. The
graph is authoritative and does not drift; this file only carries the
non-code knowledge that the graph cannot infer.

```
search_graph / query_graph    — find symbols, list classes, walk relations
trace_call_path               — who calls X, what does X call
get_code_snippet              — read source by qualified_name
detect_changes(diff)          — map a git diff to affected symbols
get_architecture              — high-level overview
```

If the graph for this repo is missing or stale:
`codebase-memory-mcp cli index_repository '{"repo_path": "/Users/ank/dev/clipy"}'`

## Bootstrap order — `AppDelegate.applicationDidFinishLaunching`

1. `AppEnvironment.replaceCurrent(...)` — register UserDefaults.
2. Login item sync, accessibility check.
3. `clipService → dataCleanService → excludeAppService → pasteService → hotKeyService.setupDefaultHotKeys()`.
4. `appLauncherService.setupHotKey()` — default ⌘Space, gated by `Constants.HotKey.appLauncherDidPreSeed`. Schedules a 200 ms `AppLauncher.shared.preload()`.
5. `inputSourceService.setupHotKeys()` — iterates `InputSource.sources`, re-registers stored KeyCombos.
6. `menuManager.setup()`.

Adding a new service requires updating all three `AppEnvironment` sites: `Environment.init`, `replaceCurrent(...)`, AND `fromStorage(...)`.

## External contracts (do NOT change without updating consumers)

- **`~/.local/share/app-launcher/var/apps.txt`** — shared with bash CLI `a` and any pre-existing Selector install. Format: `# v4` header, three tab-separated columns (original / Cyrillic-translit / Latin-translit). Read/written by `AppIndex`.
- **`~/.local/share/app-launcher/var/rates/<base>.tsv`** — FX rates, refreshed >4h via `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/<base>.json`. Used by `Calculator`.
- **`NetworkIsolation.allowedHosts`** in `AppDelegate.swift` — process-wide URLProtocol blocks all HTTP/HTTPS/FTP/WS schemes; only `cdn.jsdelivr.net` is whitelisted (for FX rates above). **Do not extend without explicit user request.**
- **UserDefaults for input-source hotkeys**: per-source key `kCPYInputSource_<id-with-dots-replaced>`. Magnet hotkey identifiers: `"InputSource:<id>"`. Magnet holds target weakly, so `InputSourceService` retains `HotKeyTarget` via `objc_setAssociatedObject`.

## Why-decisions

- **Offline-first.** Sparkle, telemetry, Realm analytics, crash upload all stripped; `URLProtocol` blocks general egress. Don't reintroduce.
- **Apple Silicon only.** `x86_64` excluded for macOS; `Scripts/strip-non-arm64-slices.sh` runs post-build.
- **Vendored deps under `vendor/`.** No CocoaPods/SPM/Bundler/Fastlane in toolchain. `vendor/` and the only build-phase script `Scripts/strip-non-arm64-slices.sh` are tracked.
- **Ported features** (`AppLauncher/`, `InputSource/`) keep Selector style — `// swiftlint:disable identifier_name` headers preserved for drop-in cherry-picks. Source-of-truth at `/Users/ank/dev/selector/selector/{ShortcutCellView,InputSourceManager}.swift`.
- **Ported singletons by design**: `AppLauncher.shared`, `AppIndex.shared`, `Calculator.shared` — multiple instances would fight over the cache file and the panel.

## Preferences Shortcuts pane (XIB invariant)

`CPYShortcutsPreferenceViewController.xib` carries five static rows in fixed-frame layout (no auto-layout): App Launcher / Main / History / Snippets in container `uTq-IP-dYk`, Clear History in container `zgf-1z-HW3`. A "Layouts" section is appended programmatically by `appendInputSourcesSection()` after XIB load — parent view resized, existing rows slide up via `flexibleMinY`. If the dynamic section would exceed ~360 px it wraps in `NSScrollView`. Adding a sixth static row means recomputing absolute y-positions.
