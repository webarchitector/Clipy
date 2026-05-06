# AGENTS.md

Read this file before changing code in this repository. Use it together with `README.md`.

## Project Snapshot

- Clipy is a macOS menu bar clipboard manager built with Swift and AppKit.
- Core app code lives in `Clipy/`; tests live in `ClipyTests/`.
- Persistence uses Realm. Reactive behavior uses RxSwift/RxCocoa. Global hotkeys use Magnet.
- Third-party code is vendored locally under `vendor/`.
- This fork is intentionally offline-first: update checks, analytics, and general remote network access are disabled in the app runtime.

## Repo Map

- `Clipy/Sources/AppDelegate.swift`: app startup, network isolation (with one-host whitelist for the launcher's currency feature), login item flow, menu actions.
- `Clipy/Sources/Services/`: clipboard monitoring, paste flow, hotkeys, cleanup, excluded apps, updates.
- `Clipy/Sources/Managers/MenuManager.swift`: menu bar UI creation and Realm-driven menu rebuilds.
- `Clipy/Sources/Models/`: Realm models for clips, folders, snippets, and app metadata.
- `Clipy/Sources/Preferences/`, `Clipy/Sources/Snippets/`, `Clipy/Xibs/`: AppKit windows, preference panes, XIB-backed UI. The `Shortcuts` pane (`Clipy/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift` + same-named XIB) hosts every hotkey: the four built-in Clipy bindings, the App Launcher binding, and a programmatically-appended "Layouts" section with one row per installed input source.
- `Clipy/Sources/AppLauncher/`: ported from the standalone Selector app. `AppLauncher.swift` (NSPanel + NSSearchField + NSTableView), `AppIndex.swift` (cache + scan + match + URL resolution + Russian-PC-layout transliteration), `Calculator.swift` (math via NSExpression, currency via cdn.jsdelivr.net), `LauncherPanel.swift` (NSPanel subclass), `AppLauncherService.swift` (Magnet hotkey wiring; default ⌘Space, gated pre-seed). Cache files at `~/.local/share/app-launcher/var/{apps.txt,rates/*.tsv}` are intentionally outside the bundle so the bash CLI `a` and any earlier Selector install share them.
- `Clipy/Sources/InputSource/`: ported from Selector. `InputSource.swift` + `TISInputSource+Additions.swift` wrap Carbon TIS; `InputSourceService.swift` registers one Magnet hotkey per input source from per-source UserDefaults keys (`kCPYInputSource_<id-with-dots-replaced>`). Hotkey identifiers are namespaced `"InputSource:<id>"`; HotKeyTarget instances are retained via `objc_setAssociatedObject` because Magnet's HotKey holds the target weakly.
- `Clipy/Resources/`: localized strings, asset catalog, color definitions.
- `Clipy/Generated/`: generated SwiftGen output. Do not hand-edit.
- `ClipyTests/`: Quick/Nimble specs.
- `Scripts/strip-non-arm64-slices.sh`: post-build cleanup for app bundle architectures.

## Working Rules

- Open `Clipy.xcworkspace`, not only `Clipy.xcodeproj`, when building or debugging the app.
- Stay within the current stack: AppKit, XIBs, Realm, RxSwift, and vendored dependencies. Do not introduce SwiftUI, SPM migrations, or dependency manager changes unless explicitly requested.
- Prefer editing app code in `Clipy/` and tests in `ClipyTests/`. Avoid touching `vendor/` unless the task is explicitly about a vendored dependency.
- Treat `Clipy/Generated/*.swift` as generated artifacts. If names, assets, colors, or strings change, update the source inputs (`swiftgen.yml`, `Clipy/Resources/Images.xcassets`, `Clipy/Resources/colors.txt`, `Clipy/Resources/en.lproj/Localizable.strings`) and regenerate through the existing SwiftGen workflow/build phase.
- Preserve the offline security posture. Do not reintroduce Sparkle, telemetry, update polling, or general network access unless explicitly requested.
- Keep Apple Silicon assumptions intact. The project excludes `x86_64` for macOS builds and strips non-`arm64` slices after build.
- Respect Realm threading rules. Do not pass live Realm objects across queues; re-open Realm on the destination thread or pass plain values.
- Many behaviors are wired through `AppEnvironment.current` and `Constants.UserDefaults`. When changing clipboard, menu, preferences, or hotkey behavior, keep service logic, defaults keys, and UI in sync. New services live on the `Environment` struct and must be added to all three call sites: the `init`, `replaceCurrent(...)` parameters in `AppEnvironment.swift`, and the `fromStorage(...)` pass-through.
- The `NetworkIsolation` URLProtocol block in `AppDelegate.swift` is process-wide: any `URLRequest` with an HTTP/HTTPS/FTP/WS scheme fails with `NSURLErrorDataNotAllowed` unless its host is in the small `allowedHosts` whitelist. Today the only whitelisted host is `cdn.jsdelivr.net` (used by `Calculator.kickOffFetch` for FX rates). Do not add hosts to that set without an explicit user request.
- App Launcher and Input Source services bootstrap from `AppDelegate.applicationDidFinishLaunching`, called sequentially after `hotKeyService.setupDefaultHotKeys()`. `AppLauncherService.setupHotKey()` schedules a 200 ms `AppLauncher.shared.preload()` so the first ⌘Space allocation isn't on the critical path. `InputSourceService.setupHotKeys()` iterates every `InputSource.sources` entry and re-registers from stored KeyCombos.
- The Shortcuts preference XIB carries five static rows (App Launcher / Main / History / Snippets at the top inside container `uTq-IP-dYk`, Clear History at the bottom inside container `zgf-1z-HW3`). Layouts rows are appended programmatically by `CPYShortcutsPreferenceViewController.appendInputSourcesSection()` after the XIB loads — the parent view is resized and existing subviews slide up via `flexibleMinY` autoresizing, freeing low-y space for the dynamic section. If the source count would push the section past 360 px, the rows are wrapped in an `NSScrollView`.
- `MenuManager` rebuilds menus from Realm notifications with debounce. If clips, snippets, or related preferences change, verify menu refresh behavior still works.
- Prefer adding or updating Quick/Nimble specs for behavior changes. Existing tests often clean up `UserDefaults` explicitly in `beforeEach` and `afterEach`.
- For localization work, keep English/base UI in XIBs and update localized `.strings` for other languages. See `.github/CONTRIBUTING.md` for the repository’s localization convention.

## Build And Test

- Main workspace scheme: `Clipy`
- When the request is "build a fresh `.app`", start with a workspace `Release` build, not with `Clipy.xcodeproj` and not with a test run.
- Preferred artifact path after a successful build: `build/DerivedData/Build/Products/Release/Clipy.app`
- Use `CODE_SIGNING_ALLOWED=NO` for local agent builds unless the user explicitly asks for a signed app.
- Prefer absolute paths when invoking `xcodebuild` from automation or sandboxed tooling to avoid workspace path resolution issues.
- List available schemes:

```sh
xcodebuild -list -workspace Clipy.xcworkspace
```

- Fastest default command for producing the app bundle:

```sh
xcodebuild \
  -workspace /Users/ank/dev/clipy/Clipy.xcworkspace \
  -scheme Clipy \
  -configuration Release \
  -derivedDataPath /Users/ank/dev/clipy/build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

- Equivalent relative-path variant if you are already in the repo root:

```sh
xcodebuild \
  -workspace Clipy.xcworkspace \
  -scheme Clipy \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

- Verify the resulting app bundle here after build:

```sh
ls -la /Users/ank/dev/clipy/build/DerivedData/Build/Products/Release/Clipy.app
```

- Run tests from the command line:

```sh
xcodebuild \
  -workspace Clipy.xcworkspace \
  -scheme Clipy \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

- SwiftLint settings live in `.swiftlint.yml`. Run SwiftLint only if it is available in the local environment.

## Change Checklist

- Did you avoid manual edits in `Clipy/Generated/`?
- Did you avoid touching `vendor/` unless necessary?
- Did you preserve the offline/network-blocking behavior? (`NetworkIsolation.allowedHosts` should change only on explicit user request.)
- Did you keep Realm threading and writes safe?
- Did you update tests, or note why tests were not updated?
- If a new file landed in `Clipy/Sources/`, did you also add the file reference to `Clipy.xcodeproj/project.pbxproj` so the Xcode target picks it up? The fastest tool is the `xcodeproj` Ruby gem; an example invocation lives in `docs/superpowers/plans/2026-05-06-app-launcher-port.md` (Task 16).
- If a new service was added to `AppEnvironment.Environment`, did you update `Environment.init`, `AppEnvironment.replaceCurrent(...)`, AND `AppEnvironment.fromStorage(...)`?

## App Launcher / Input Sources Editing Guidance

When editing the launcher or input-source code:

- The launcher and input-source ports cite the Selector source-of-truth at `/Users/ank/dev/selector/selector/ShortcutCellView.swift` (lines 611–1426) and `/Users/ank/dev/selector/selector/InputSourceManager.swift` for ongoing reference. Diverge from those files only with reason — keeping them aligned makes future cherry-picks of fixes from either project trivial.
- The full design and rationale for the launcher port live in `docs/superpowers/specs/2026-05-06-app-launcher-port-design.md`; the executed task list is in `docs/superpowers/plans/2026-05-06-app-launcher-port.md`. Read them before touching `AppLauncher/`.
- `AppLauncher.shared` and `Calculator.shared` and `AppIndex.shared` are singletons by design — multiple instances would fight over the cache file and the panel.
- `AppLauncher.rebuildDidFinish()` is called from background workers (`AppIndex.buildIndexAsync`, `Calculator.kickOffFetch`) once their main-thread completion lands. It re-applies the current filter only if the panel is visible. Don't change this contract without updating both callers.
- The `~/.local/share/app-launcher/var/` cache is **shared with an external bash CLI `a`** and (during transition) any pre-existing Selector install. The on-disk `apps.txt` format (`# v4` header, three tab-separated columns: original / Cyrillic-translit / Latin-translit) is a public contract — don't reorder columns or change the header without changing the consumer too.
- Input source hotkeys deduplicate at change time: setting source A's combo to one already used by source B clears B (both in UserDefaults and in the in-memory `registrations` map and the visual `RecordView`). The Shortcuts pane mirrors this in its delegate.
- The Shortcuts XIB has five static rows. Adding a sixth static row means recomputing absolute y-positions: the top edge of the `uTq-IP-dYk` container plus its height must stay below the y of the "Menu" header by at least 8 px (no auto-layout, all positions are fixed-frame).
- SwiftLint disables `identifier_name` per file in `AppLauncher/` and `InputSource/` source via `// swiftlint:disable identifier_name` headers. Selector's source-of-truth uses many short locals (`p`, `s`, `q`, …); keeping them disabled here preserves drop-in portability.
