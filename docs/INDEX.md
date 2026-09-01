# Project Index

For code navigation (classes, methods, call paths, references) use the
`codebase-memory-mcp` graph — project key `Volumes-dev-code-dev-clipy`. The
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
`codebase-memory-mcp cli index_repository '{"repo_path": "/Volumes/dev/code-dev/clipy"}'`

## Bootstrap order — `AppDelegate.applicationDidFinishLaunching`

1. `AppEnvironment.replaceCurrent(...)` — register UserDefaults.
2. Login item sync. Accessibility and Input Monitoring are not requested at launch.
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
- **Local patches to vendored deps.** Some files under `vendor/` carry Clipy-side modifications — do not overwrite them blindly when refreshing a dep from upstream:
  - `vendor/Dependencies/Magnet/Lib/Magnet/HotKey.swift` + `HotKeyCenter.swift` — added `HotKey.registeredKeyCode: CGKeyCode?` set in `HotKeyCenter.register()` and cleared in `unregister()`. Stores the keyCode Carbon was registered with so HID-level dispatchers (`HIDHotKeyTap`) match against a layout-stable value instead of `keyCombo.currentKeyCode`, which Sauce recomputes per call against the active layout and drifts after keyboard-layout changes. Symptom that drove the patch: `Alt+Cmd+J`/`K` layout-switching hotkeys silently failing every other press in mixed-layout sessions.
- **Ported features** (`AppLauncher/`, `InputSource/`) keep Selector style — `// swiftlint:disable identifier_name` headers preserved for drop-in cherry-picks. Source-of-truth at `/Users/ank/dev/selector/selector/{ShortcutCellView,InputSourceManager}.swift`.
- **Ported singletons by design**: `AppLauncher.shared`, `AppIndex.shared`, `Calculator.shared` — multiple instances would fight over the cache file and the panel.
- **Popup NSMenu key overrides go through the HID-level CGEvent tap, not the local NSEvent monitor.** NSMenu's tracker pulls events directly from the OS event queue, so `addLocalMonitorForEvents` substitutes and `NSApp.postEvent` never reach it (the local monitor is fine for `cancelTrackingWithoutAnimation()` side effects — menu-type switching, app-launcher hotkey — but cannot rewrite or suppress what NSMenu sees). `menuManagerEventTapCallback` rewrites `j`/`k` (keyCode 38/40) to ↓/↑ (125/126) in place and consumes `O`/right-click to open clips in the default app. Requires Accessibility; without it those overrides degrade silently.
- **`vendor/LoginServiceKit` Swift 6 audit (2026-05) — clean.** Pure static methods over Carbon LaunchServices APIs, no captured state, no closures crossing isolation boundaries. The fork stays at v2.2.0 / Swift 5.0 intentionally for upstream cherry-pick parity. Open API debt: `LSSharedFileListCreate` and friends deprecated since macOS 10.11; a port to `SMAppService` (10.13+) is desirable but needs an entitlements review and is its own task.

## Preferences Shortcuts pane (XIB invariant)

`CPYShortcutsPreferenceViewController.xib` carries five static rows in fixed-frame layout (no auto-layout): App Launcher / Main / History / Snippets in container `uTq-IP-dYk`, Clear History in container `zgf-1z-HW3`. A "Layouts" section is appended programmatically by `appendInputSourcesSection()` after XIB load — parent view resized, existing rows slide up via `flexibleMinY`. If the dynamic section would exceed ~360 px it wraps in `NSScrollView`. Adding a sixth static row means recomputing absolute y-positions.
