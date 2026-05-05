# AGENTS.md

Read this file before changing code in this repository. Use it together with `README.md`.

## Project Snapshot

- Clipy is a macOS menu bar clipboard manager built with Swift and AppKit.
- Core app code lives in `Clipy/`; tests live in `ClipyTests/`.
- Persistence uses Realm. Reactive behavior uses RxSwift/RxCocoa. Global hotkeys use Magnet.
- Third-party code is vendored locally under `vendor/`.
- This fork is intentionally offline-first: update checks, analytics, and general remote network access are disabled in the app runtime.

## Repo Map

- `Clipy/Sources/AppDelegate.swift`: app startup, network isolation, login item flow, menu actions.
- `Clipy/Sources/Services/`: clipboard monitoring, paste flow, hotkeys, cleanup, excluded apps, updates.
- `Clipy/Sources/Managers/MenuManager.swift`: menu bar UI creation and Realm-driven menu rebuilds.
- `Clipy/Sources/Models/`: Realm models for clips, folders, snippets, and app metadata.
- `Clipy/Sources/Preferences/`, `Clipy/Sources/Snippets/`, `Clipy/Xibs/`: AppKit windows, preference panes, XIB-backed UI.
- `Clipy/Resources/`: localized strings, asset catalog, color definitions.
- `Clipy/Generated/`: generated SwiftGen output. Do not hand-edit.
- `ClipyTests/`: Quick/Nimble specs.
- `Scripts/strip-non-arm64-slices.sh`: post-build cleanup for app bundle architectures.
- `Scripts/strip-pincache-from-vendor.sh`: post-bootstrap cleanup that removes PINCache/PINOperation linker, header search and embed entries from `vendor/Dependencies/Target Support Files/Pods-{Clipy,ClipyTests}/*.xcconfig` and `Pods-Clipy-frameworks.sh`. PINCache was replaced at runtime by `Clipy/Sources/Services/ThumbnailCache.swift`; this script keeps the unused framework out of the linked/embedded build. Idempotent — run any time `vendor/Dependencies` is regenerated.

## Working Rules

- Open `Clipy.xcworkspace`, not only `Clipy.xcodeproj`, when building or debugging the app.
- Stay within the current stack: AppKit, XIBs, Realm, RxSwift, and vendored dependencies. Do not introduce SwiftUI, SPM migrations, or dependency manager changes unless explicitly requested.
- Prefer editing app code in `Clipy/` and tests in `ClipyTests/`. Avoid touching `vendor/` unless the task is explicitly about a vendored dependency.
- Treat `Clipy/Generated/*.swift` as generated artifacts. If names, assets, colors, or strings change, update the source inputs (`swiftgen.yml`, `Clipy/Resources/Images.xcassets`, `Clipy/Resources/colors.txt`, `Clipy/Resources/en.lproj/Localizable.strings`) and regenerate through the existing SwiftGen workflow/build phase.
- Preserve the offline security posture. Do not reintroduce Sparkle, telemetry, update polling, or general network access unless explicitly requested.
- Keep Apple Silicon assumptions intact. The project excludes `x86_64` for macOS builds and strips non-`arm64` slices after build.
- Respect Realm threading rules. Do not pass live Realm objects across queues; re-open Realm on the destination thread or pass plain values.
- Many behaviors are wired through `AppEnvironment.current` and `Constants.UserDefaults`. When changing clipboard, menu, preferences, or hotkey behavior, keep service logic, defaults keys, and UI in sync.
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
- Did you preserve the offline/network-blocking behavior?
- Did you keep Realm threading and writes safe?
- Did you update tests, or note why tests were not updated?
