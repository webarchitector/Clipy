<div align="center">
  <img src="./Resources/clipy_logo.png" width="400" alt="Clipy logo">
</div>

# Clipy

> Before making changes, read [AGENTS.md](./AGENTS.md) first. It contains project-specific instructions for contributors and coding agents.

Clipboard extension for macOS.

Clipy is a clipboard extension for macOS that lives in the menu bar and keeps a searchable history of copied text and snippets. It is designed to make repeated copy/paste work faster: you can recall previous clipboard entries, organize snippets, and paste saved content without leaving your current app.

## What the App Does

- Stores clipboard history locally on the Mac.
- Lets you reopen and paste previous copied items from the menu bar.
- Supports reusable snippets and folders for frequently used text.
- Keeps the workflow lightweight and keyboard-driven.

## Screenshots

Main Clipy interface:

<img src="https://clipy-app.com/img/screenshot1.png" width="640" alt="Clipy screenshot">

## What Changed

- The build toolchain no longer requires Ruby, Bundler, Fastlane, Danger, or CocoaPods.
- Dependencies are vendored locally in `vendor/Dependencies/`.

## Install

You can install Clipy either from a prebuilt app bundle or by building it from source.

### Install a Built App

1. Build or obtain a `Clipy.app` bundle.
2. Move `Clipy.app` to `/Applications`.
3. Launch it from Finder.
4. If macOS blocks the first launch because the app is unsigned, right-click the app, choose `Open`, and confirm.

## Build from Source

### Requirements

- macOS 11 or later.
- Xcode with the macOS SDK and command line tools installed.
- An Apple Silicon Mac. The current project excludes `x86_64` for macOS builds and strips non-`arm64` slices from the final app bundle.
- No Ruby, Bundler, Fastlane, or CocoaPods setup is required. Dependencies are already vendored in the repository.

### Build in Xcode

1. Open `Clipy.xcworkspace` in Xcode.
2. Select the `Clipy` scheme.
3. Select the `My Mac` destination.
4. Use `Product > Build` for a local build or `Product > Archive` to create a distributable archive.

The built app bundle will be available in Xcode DerivedData under `Build/Products/<Debug|Release>/Clipy.app`.

### Build from the Command Line

```sh
xcodebuild \
  -workspace Clipy.xcworkspace \
  -scheme Clipy \
  -configuration Release \
  build \
  SYMROOT=$(pwd)/build
```

The resulting app bundle will be at `build/Release/Clipy.app`.

To do a full clean rebuild:

```sh
rm -rf build/Release/Clipy.app
xcodebuild \
  -workspace Clipy.xcworkspace \
  -scheme Clipy \
  -configuration Release \
  build \
  SYMROOT=$(pwd)/build
```

For distribution outside your machine, archive and sign the app in Xcode with your own team and signing settings.

## Security Profile

This fork was hardened to avoid unsolicited network activity and to reduce remote exposure.

- Automatic update checks were removed.
- Sparkle and related update assets were removed from the app bundle.
- Remote network requests are blocked in the application runtime.
- Realm analytics and update checks are disabled.
- Crash-report upload options were removed from the UI.
- The app does not expose remote APIs or network listener features.

Operationally, this release is designed to work as an offline local utility.

## License

Clipy is available under the MIT license. See [LICENSE](./LICENSE).

Icons remain copyrighted by their respective authors.

## Credits

Original Clipy and ClipMenu work remains credited to their original authors and contributors.
