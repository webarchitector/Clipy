# App Launcher Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the AppLauncher feature (apps + math + currency, ⌘Space hotkey) from `/Users/ank/dev/selector/selector/ShortcutCellView.swift` into Clipy as a new `AppLauncher/` module integrated through Clipy's existing `AppEnvironment`/`Magnet` patterns.

**Architecture:** Five new Swift files in `Clipy/Sources/AppLauncher/`. Pure logic (translit, filter matching, math eval, currency parsing) is split into static functions and unit-tested with Quick/Nimble. Stateful AppKit/Magnet glue (NSPanel, hotkey registration) is verified manually after build. One narrow exception added to existing `NetworkIsolation` URLProtocol block to permit FX rate fetching from `cdn.jsdelivr.net`.

**Tech Stack:** Swift 5, AppKit, Magnet (vendored), KeyHolder (vendored), Quick/Nimble (vendored), Xcode workspace build.

**Source spec:** `/Volumes/dev/code-dev/clipy/docs/superpowers/specs/2026-05-06-app-launcher-port-design.md`
**Source-of-truth implementation:** `/Users/ank/dev/selector/selector/ShortcutCellView.swift` (lines 611–1426 contain AppLauncher + LauncherPanel + AppLauncherShortcut). Line ranges referenced below assume that file at commit `2990604` or later.

---

## Task 1: Pre-flight build verification

Confirm the clipy `develop` branch builds cleanly before any changes. If it doesn't, stop and report — the rest of the plan assumes a green starting state.

**Files:** none (read-only sanity check)

- [ ] **Step 1: Verify clean working tree on `develop`**

```bash
cd /Volumes/dev/code-dev/clipy
git status
git rev-parse --abbrev-ref HEAD
```

Expected: `working tree clean`, branch `develop`. If dirty, stop and ask the user.

- [ ] **Step 2: Build Release**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace /Volumes/dev/code-dev/clipy/Clipy.xcworkspace \
  -scheme Clipy \
  -configuration Release \
  -derivedDataPath /Volumes/dev/code-dev/clipy/build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. If it fails, stop and report.

- [ ] **Step 3: Run existing tests**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace Clipy.xcworkspace \
  -scheme Clipy \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`. If failures appear pre-existing, document them and proceed (we're porting, not fixing existing bugs); if the build itself fails, stop.

---

## Task 2: Add `Constants.HotKey.appLauncherKeyCombo`

**Files:**
- Modify: `Clipy/Sources/Constants.swift`

- [ ] **Step 1: Add the new hotkey constant**

Open `Clipy/Sources/Constants.swift`. Find the `struct HotKey { ... }` block. After the `clearHistoryKeyCombo` line, add:

```swift
        static let appLauncherKeyCombo = "kCPYHotKeyAppLauncherKeyCombo"
        static let appLauncherDidPreSeed = "kCPYHotKeyAppLauncherDidPreSeed"
```

The first key holds the archived `KeyCombo`; the second is a one-shot flag that records that we have already pre-seeded ⌘Space (so a user who later clears the shortcut stays cleared rather than getting it re-seeded on every launch).

- [ ] **Step 2: Compile-check**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. (No callers of the new constants yet, so no behaviour change.)

- [ ] **Step 3: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/Constants.swift
git commit -m "add app launcher hotkey defaults keys"
```

---

## Task 3: Whitelist `cdn.jsdelivr.net` in `NetworkIsolation`

**Files:**
- Modify: `Clipy/Sources/AppDelegate.swift:23-58`

- [ ] **Step 1: Update `NetworkIsolation` to allow one host**

Replace the existing `NetworkIsolation` enum (currently lines 23–39) with:

```swift
private enum NetworkIsolation {
    private static let blockedSchemes = Set(["ftp", "ftps", "http", "https", "ws", "wss"])

    /// App Launcher's currency feature is the only outbound network egress
    /// in the entire process. Adding a host here is the only sanctioned way
    /// to pierce the otherwise process-wide URLProtocol block — see
    /// docs/superpowers/specs/2026-05-06-app-launcher-port-design.md.
    private static let allowedHosts: Set<String> = [
        "cdn.jsdelivr.net"
    ]

    static func configureProcess() {
        setenv("REALM_DISABLE_ANALYTICS", "1", 1)
        setenv("REALM_DISABLE_UPDATE_CHECKER", "1", 1)
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 0
        _ = URLProtocol.registerClass(RemoteNetworkBlockerURLProtocol.self)
    }

    static func shouldBlock(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        if let host = url?.host?.lowercased(), allowedHosts.contains(host) {
            return false
        }
        return blockedSchemes.contains(scheme)
    }
}
```

The only behavioural change: requests to `cdn.jsdelivr.net` (any scheme) bypass the URLProtocol block. Everything else stays blocked.

- [ ] **Step 2: Build**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppDelegate.swift
git commit -m "whitelist cdn.jsdelivr.net for app launcher fx rates"
```

---

## Task 4: Create `AppIndex.swift` with translit tables and pure-logic match

This task ports translit tables, the `AppEntry` struct, and the static `matches` predicate. Stateful FS code (scan/cache/resolveURL) is a separate task.

**Files:**
- Create: `Clipy/Sources/AppLauncher/AppIndex.swift`

- [ ] **Step 1: Create the folder and the file**

```bash
mkdir -p /Volumes/dev/code-dev/clipy/Clipy/Sources/AppLauncher
```

Create `Clipy/Sources/AppLauncher/AppIndex.swift` with the following content:

```swift
//
//  AppIndex.swift
//
//  Clipy AppLauncher — application discovery, cache, and matching.
//

import Foundation

struct AppEntry {
    let original: String
    let cyr: String
    let lat: String
}

/// Source of all installed-app names. Maintains a cached `apps.txt` index
/// shared with the bash CLI `a` (path under `~/.local/share/app-launcher/var/`).
/// Only the pure-logic surface is in this section; FS-touching code is added
/// in a follow-up task.
final class AppIndex {

    static let shared = AppIndex()

    /// Single source of truth for application source directories. `scanDepth`
    /// matches the recursion limit the scanner uses: user-visible roots can
    /// contain `Utilities/`, `Setapp/`, etc. (depth 3); `/System/Library/CoreServices`
    /// only needs Finder.app at depth 1.
    static let appSourceRoots: [(path: String, scanDepth: Int)] = [
        ("/Applications", 3),
        ("/System/Applications", 3),
        (NSHomeDirectory() + "/Applications", 3),
        ("/System/Library/CoreServices", 1)
    ]

    // MARK: - Pure-logic match predicate

    /// Pre-lowered query, contains-match against any of three indexes.
    /// `query` MUST already be lowercased — caller does it once per filter pass.
    static func matches(_ entry: AppEntry, query qlc: String) -> Bool {
        return entry.original.lowercased().contains(qlc)
            || entry.cyr.contains(qlc)
            || entry.lat.contains(qlc)
    }

    // MARK: - Transliteration (Russian PC keyboard layout)

    /// Cyrillic → Latin map keyed by physical Russian-PC-layout position.
    /// Both upper- and lower-case Cyrillic glyphs map to the same lowercase
    /// Latin character; the inverse `latToCyr` keeps only the lowercase
    /// entries so transliteration in either direction yields lowercase ASCII.
    static let cyrToLat: [Character: Character] = [
        "Й": "q", "й": "q", "Ц": "w", "ц": "w", "У": "e", "у": "e",
        "К": "r", "к": "r", "Е": "t", "е": "t", "Н": "y", "н": "y",
        "Г": "u", "г": "u", "Ш": "i", "ш": "i", "Щ": "o", "щ": "o", "З": "p", "з": "p",
        "Ф": "a", "ф": "a", "Ы": "s", "ы": "s", "В": "d", "в": "d",
        "А": "f", "а": "f", "П": "g", "п": "g", "Р": "h", "р": "h",
        "О": "j", "о": "j", "Л": "k", "л": "k", "Д": "l", "д": "l",
        "Я": "z", "я": "z", "Ч": "x", "ч": "x", "С": "c", "с": "c",
        "М": "v", "м": "v", "И": "b", "и": "b", "Т": "n", "т": "n",
        "Ь": "m", "ь": "m"
    ]

    /// Inverse of cyrToLat keyed by lowercase Latin (only lowercase Cyrillic
    /// entries kept so the result is lowercase). Used to render an app's
    /// Latin name as the Cyrillic glyphs that appear if the user keeps the
    /// Russian layout active.
    static let latToCyr: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (cy, lt) in cyrToLat where cy.isLowercase { m[lt] = cy }
        return m
    }()

    static func translitLatinToCyrillic(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.lowercased() {
            out.append(latToCyr[ch] ?? ch)
        }
        return out
    }

    static func translitCyrillicToLatin(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            out.append(cyrToLat[ch] ?? ch)
        }
        return out
    }
}
```

This file does NOT yet contain the FS scanner, cache reader, or `resolveURL` — those live in Task 7 to keep this task focused on the pure logic that we test in Tasks 5 and 6.

- [ ] **Step 2: Commit (file lives on disk; not yet in Xcode project — that's Task 16)**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppLauncher/AppIndex.swift
git commit -m "add AppIndex transliteration tables and match predicate"
```

---

## Task 5: Translit unit tests (`AppIndexTranslitSpec`)

**Files:**
- Create: `ClipyTests/AppLauncher/AppIndexTranslitSpec.swift`

- [ ] **Step 1: Create the folder and the spec**

```bash
mkdir -p /Volumes/dev/code-dev/clipy/ClipyTests/AppLauncher
```

Create `ClipyTests/AppLauncher/AppIndexTranslitSpec.swift`:

```swift
import Quick
import Nimble
@testable import Clipy

class AppIndexTranslitSpec: QuickSpec {
    override func spec() {
        describe("translit tables") {

            it("maps lowercase Latin to lowercase Cyrillic via the Russian PC layout") {
                expect(AppIndex.latToCyr["t"]) == Character("е")
                expect(AppIndex.latToCyr["m"]) == Character("ь")
                expect(AppIndex.latToCyr["a"]) == Character("ф")
                expect(AppIndex.latToCyr["i"]) == Character("ш")
                expect(AppIndex.latToCyr["l"]) == Character("д")
            }

            it("maps both cases of Cyrillic to the same lowercase Latin") {
                expect(AppIndex.cyrToLat["Е"]) == Character("t")
                expect(AppIndex.cyrToLat["е"]) == Character("t")
                expect(AppIndex.cyrToLat["Ь"]) == Character("m")
                expect(AppIndex.cyrToLat["ь"]) == Character("m")
            }
        }

        describe("translitLatinToCyrillic") {

            it("renders an app's Latin name as Russian-PC-layout Cyrillic") {
                expect(AppIndex.translitLatinToCyrillic("Mail")) == "ьфшд"
                expect(AppIndex.translitLatinToCyrillic("Terminal")) == "еукьштфд"
                expect(AppIndex.translitLatinToCyrillic("Safari")) == "ыфафкш"
            }

            it("is lowercase regardless of input case") {
                expect(AppIndex.translitLatinToCyrillic("MAIL")) == "ьфшд"
            }

            it("passes characters that have no mapping through unchanged") {
                expect(AppIndex.translitLatinToCyrillic("Mail.app")) == "ьфшд.фзз"
                expect(AppIndex.translitLatinToCyrillic("a1b2")) == "ф1и2"
            }
        }

        describe("translitCyrillicToLatin") {

            it("converts both upper- and lower-case Cyrillic to lowercase Latin") {
                expect(AppIndex.translitCyrillicToLatin("ЬФШД")) == "MAIL".lowercased()
                expect(AppIndex.translitCyrillicToLatin("ьфшд")) == "mail"
            }

            it("passes Latin unchanged") {
                expect(AppIndex.translitCyrillicToLatin("usd")) == "usd"
            }
        }

        describe("round-trip") {

            it("Latin → Cyrillic → Latin preserves lowercased form") {
                let names = ["mail", "terminal", "safari"]
                for n in names {
                    let cy = AppIndex.translitLatinToCyrillic(n)
                    expect(AppIndex.translitCyrillicToLatin(cy)) == n
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add ClipyTests/AppLauncher/AppIndexTranslitSpec.swift
git commit -m "test AppIndex transliteration round-trip"
```

(Tests cannot run yet — file is not in the Xcode project. Both files get added in Task 16.)

---

## Task 6: Filter-matching unit tests (`AppIndexFilterSpec`)

**Files:**
- Create: `ClipyTests/AppLauncher/AppIndexFilterSpec.swift`

- [ ] **Step 1: Create the spec**

```swift
import Quick
import Nimble
@testable import Clipy

class AppIndexFilterSpec: QuickSpec {
    override func spec() {

        let mail = AppEntry(
            original: "Mail",
            cyr: AppIndex.translitLatinToCyrillic("Mail"),
            lat: "mail"
        )
        let terminal = AppEntry(
            original: "Terminal",
            cyr: AppIndex.translitLatinToCyrillic("Terminal"),
            lat: "terminal"
        )

        describe("AppIndex.matches") {

            context("Latin queries") {
                it("matches lowercase substring against original") {
                    expect(AppIndex.matches(terminal, query: "term")) == true
                }
                it("is case-insensitive — caller pre-lowers") {
                    expect(AppIndex.matches(terminal, query: "TERM".lowercased())) == true
                }
                it("misses when no index contains the substring") {
                    expect(AppIndex.matches(terminal, query: "browser")) == false
                }
            }

            context("Cyrillic transliteration matching") {
                it("matches the Russian-PC-layout transliteration of the name") {
                    // Mail in Cyrillic = ьфшд
                    expect(AppIndex.matches(mail, query: "ьфшд")) == true
                }
                it("matches the uppercase Cyrillic query after lowercasing") {
                    let qlc = "ЬФШД".lowercased()
                    expect(AppIndex.matches(mail, query: qlc)) == true
                }
                it("matches a partial Cyrillic substring") {
                    expect(AppIndex.matches(mail, query: "ьф")) == true
                }
            }

            context("lat index") {
                it("matches a substring of the lowercase Latin name") {
                    expect(AppIndex.matches(mail, query: "mai")) == true
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add ClipyTests/AppLauncher/AppIndexFilterSpec.swift
git commit -m "test AppIndex filter matching against three indexes"
```

---

## Task 7: AppIndex stateful surface — scan, cache, mtime, resolveURL

This task adds the FS-touching machinery: `apps` storage, scan, cache I/O, mtime-based invalidation, async/sync rebuild, source-changed detection, and `resolveURL`. None of it is unit-tested — all of it is exercised by the manual smoke test in Task 22.

The code here is a **direct port of selector code** with no functional changes. Use `/Users/ank/dev/selector/selector/ShortcutCellView.swift` as the reference.

**Files:**
- Modify: `Clipy/Sources/AppLauncher/AppIndex.swift` (extend the existing file)

- [ ] **Step 1: Append the stateful surface to `AppIndex.swift`**

After the existing `translitCyrillicToLatin` static func (still inside the `AppIndex` class), append the following sections. Each one ports a labelled selector section verbatim, adjusted only for the `appSourceRoots` reference and the `apps` storage being instance-state.

```swift
    // MARK: - Stateful storage

    private var apps: [AppEntry] = []
    private var appsLoadedMtime: Date?
    private var indexBuildInFlight = false

    private var cacheDir: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.local/share/app-launcher/var", isDirectory: true)
    }
    private var appsFile: URL { cacheDir.appendingPathComponent("apps.txt") }

    /// Convenience for the launcher's filter pass — running apps appear first
    /// with a `●` dot, but that decoration is in the UI; this method just
    /// returns the matched entries in (running-first, by-cache-order) sequence.
    func match(query: String, runningNames: Set<String>) -> [(name: String, running: Bool)] {
        var running: [(String, Bool)] = []
        var rest: [(String, Bool)] = []
        if query.isEmpty {
            for app in apps {
                let isRunning = runningNames.contains(app.original)
                let pair = (app.original, isRunning)
                if isRunning { running.append(pair) } else { rest.append(pair) }
            }
        } else {
            let qlc = query.lowercased()
            for app in apps {
                guard AppIndex.matches(app, query: qlc) else { continue }
                let isRunning = runningNames.contains(app.original)
                let pair = (app.original, isRunning)
                if isRunning { running.append(pair) } else { rest.append(pair) }
            }
        }
        return running + rest
    }

    // MARK: - Reload + cache I/O
    //
    // Direct port of selector AppLauncher.reloadAppsIfNeeded /
    // loadAppsCacheFromDisk / buildIndexSync / buildIndexAsync /
    // appSourcesChanged / scanAppNames / writeAppsFile.
    // See: /Users/ank/dev/selector/selector/ShortcutCellView.swift:841-998.

    func reloadIfNeeded() {
        let fm = FileManager.default

        if !fm.fileExists(atPath: appsFile.path) {
            buildIndexSync()
        } else if let mtime = (try? fm.attributesOfItem(atPath: appsFile.path)[.modificationDate]) as? Date {
            if appSourcesChanged(since: mtime) || Date().timeIntervalSince(mtime) > 24 * 3600 {
                buildIndexAsync()
            }
        }

        loadAppsCacheFromDisk()
    }

    private func loadAppsCacheFromDisk() {
        let fm = FileManager.default
        let mtime = (try? fm.attributesOfItem(atPath: appsFile.path)[.modificationDate]) as? Date
        if let cached = appsLoadedMtime, mtime == cached, !apps.isEmpty { return }
        appsLoadedMtime = mtime

        var loaded: [AppEntry] = []
        if let text = try? String(contentsOf: appsFile, encoding: .utf8) {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if line.hasPrefix("#") { continue }
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3 {
                    loaded.append(AppEntry(original: String(parts[0]),
                                           cyr: String(parts[1]),
                                           lat: String(parts[2])))
                }
            }
        }
        apps = loaded
    }

    private func buildIndexSync() {
        let names = scanAppNames()
        writeAppsFile(names: names)
    }

    private func buildIndexAsync() {
        if indexBuildInFlight { return }
        indexBuildInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let names = self.scanAppNames()
            DispatchQueue.main.async {
                self.writeAppsFile(names: names)
                self.appsLoadedMtime = nil
                self.indexBuildInFlight = false
                self.loadAppsCacheFromDisk()
                AppLauncher.shared.rebuildDidFinish()
            }
        }
    }

    private func appSourcesChanged(since cacheMtime: Date) -> Bool {
        let fm = FileManager.default
        for (root, scanDepth) in AppIndex.appSourceRoots {
            if let m = (try? fm.attributesOfItem(atPath: root)[.modificationDate]) as? Date,
               m > cacheMtime {
                return true
            }
            if scanDepth <= 1 { continue }
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where !entry.hasSuffix(".app") {
                let subPath = "\(root)/\(entry)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: subPath, isDirectory: &isDir),
                      isDir.boolValue,
                      let m = (try? fm.attributesOfItem(atPath: subPath)[.modificationDate]) as? Date,
                      m > cacheMtime else { continue }
                return true
            }
        }
        return false
    }

    private func scanAppNames() -> [String] {
        let fm = FileManager.default
        var names = Set<String>()

        for (root, maxDepth) in AppIndex.appSourceRoots {
            guard let en = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in en {
                if en.level > maxDepth {
                    en.skipDescendants()
                    continue
                }
                if url.pathExtension == "app" {
                    names.insert(url.deletingPathExtension().lastPathComponent)
                    en.skipDescendants()
                }
            }
        }
        return Array(names).sorted()
    }

    private func writeAppsFile(names: [String]) {
        var lines = ["# v4"]
        lines.reserveCapacity(names.count + 1)
        for name in names {
            let cyr = AppIndex.translitLatinToCyrillic(name)
            let lat = AppIndex.translitCyrillicToLatin(name).lowercased()
            lines.append("\(name)\t\(cyr)\t\(lat)")
        }
        let body = lines.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? body.write(to: appsFile, atomically: true, encoding: .utf8)
    }

    // MARK: - URL resolution
    //
    // See: /Users/ank/dev/selector/selector/ShortcutCellView.swift:1195-1227.

    func resolveURL(named name: String) -> URL? {
        let fm = FileManager.default
        for (dir, _) in AppIndex.appSourceRoots {
            let url = URL(fileURLWithPath: "\(dir)/\(name).app")
            if fm.fileExists(atPath: url.path) { return url }
        }
        for (root, maxDepth) in AppIndex.appSourceRoots where maxDepth > 1 {
            guard let en = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in en {
                if en.level > maxDepth {
                    en.skipDescendants()
                    continue
                }
                if url.pathExtension == "app" {
                    en.skipDescendants()
                    if url.deletingPathExtension().lastPathComponent == name {
                        return url
                    }
                }
            }
        }
        return nil
    }
```

The file now contains everything the launcher needs from "the index". `AppLauncher.shared.rebuildDidFinish()` is forward-declared — `AppLauncher` is implemented in Task 13.

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppLauncher/AppIndex.swift
git commit -m "add AppIndex scan, cache, and resolveURL"
```

(File compiles only after `AppLauncher.shared` exists. Task 13 closes that loop. Tasks 5 and 6 tests still don't run until Task 16.)

---

## Task 8: `Calculator.swift` skeleton with static math + currency parsing

This task ports the pure parsing/eval logic. Stateful currency fetching is a follow-up task.

**Files:**
- Create: `Clipy/Sources/AppLauncher/Calculator.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  Calculator.swift
//
//  Clipy AppLauncher — math evaluator + currency conversion.
//

import Foundation

final class Calculator {

    static let shared = Calculator()

    // MARK: - Math
    //
    // See: /Users/ank/dev/selector/selector/ShortcutCellView.swift:1244-1276.

    static func evaluateMath(_ expr: String) -> String? {
        var normalized = expr
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "^", with: "**")
        if let r = try? NSRegularExpression(pattern: #"sqrt\s*\(([^()]*)\)"#) {
            while let m = r.firstMatch(in: normalized,
                                       range: NSRange(normalized.startIndex..<normalized.endIndex,
                                                      in: normalized)),
                  let full = Range(m.range(at: 0), in: normalized),
                  let arg = Range(m.range(at: 1), in: normalized) {
                normalized.replaceSubrange(full, with: "((\(normalized[arg]))**0.5)")
            }
        }
        let nsExpr = NSExpression(format: normalized)
        if let value = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber {
            let v = value.doubleValue
            if v.isNaN || v.isInfinite { return nil }
            if v.truncatingRemainder(dividingBy: 1) == 0 && abs(v) < 1e15 {
                return String(format: "%.0f", v)
            }
            return String(format: "%.6g", v)
        }
        return nil
    }

    // MARK: - Currency parsing
    //
    // See: /Users/ank/dev/selector/selector/ShortcutCellView.swift:1284-1295.

    static func parseCurrency(_ s: String) -> (amount: Double, from: String, to: String)? {
        let pattern = #"^\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]{3,4})\s*([a-zA-Z]{3,4})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = regex.firstMatch(in: s, range: range), m.numberOfRanges == 4,
              let r1 = Range(m.range(at: 1), in: s),
              let r2 = Range(m.range(at: 2), in: s),
              let r3 = Range(m.range(at: 3), in: s),
              let amount = Double(s[r1]) else { return nil }
        return (amount, String(s[r2]).lowercased(), String(s[r3]).lowercased())
    }

    static func formatRate(_ x: Double) -> String {
        x.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", x)
            : String(format: "%g", x)
    }
}
```

`evaluateMath`'s body inside selector is wrapped in `do { … } catch { return nil }` — `NSExpression(format:)` *does* throw via NSException for malformed input, but the Swift bridge surfaces it as a runtime crash, not a thrown error. In the selector the `do/catch` is therefore dead code; we drop it here. Build will confirm.

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppLauncher/Calculator.swift
git commit -m "add Calculator math eval and currency parser"
```

---

## Task 9: Math unit tests (`CalculatorMathSpec`)

**Files:**
- Create: `ClipyTests/AppLauncher/CalculatorMathSpec.swift`

- [ ] **Step 1: Create the spec**

```swift
import Quick
import Nimble
@testable import Clipy

class CalculatorMathSpec: QuickSpec {
    override func spec() {
        describe("Calculator.evaluateMath") {

            it("evaluates basic arithmetic") {
                expect(Calculator.evaluateMath("1+2")) == "3"
                expect(Calculator.evaluateMath("(1+2)*3")) == "9"
                expect(Calculator.evaluateMath("10/4")) == "2.5"
            }

            it("supports the ^ alias for exponentiation") {
                expect(Calculator.evaluateMath("2^10")) == "1024"
            }

            it("handles sqrt() via a regex pre-pass") {
                expect(Calculator.evaluateMath("sqrt(4)")) == "2"
                expect(Calculator.evaluateMath("sqrt(2)")) == "1.41421"
            }

            it("returns nil for divide-by-zero") {
                expect(Calculator.evaluateMath("1/0")).to(beNil())
            }

            it("formats integral results without a decimal") {
                expect(Calculator.evaluateMath("3")) == "3"
                expect(Calculator.evaluateMath("3.0")) == "3"
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add ClipyTests/AppLauncher/CalculatorMathSpec.swift
git commit -m "test Calculator math evaluation"
```

---

## Task 10: Currency parsing unit tests (`CalculatorCurrencySpec`)

**Files:**
- Create: `ClipyTests/AppLauncher/CalculatorCurrencySpec.swift`

- [ ] **Step 1: Create the spec**

```swift
import Quick
import Nimble
@testable import Clipy

class CalculatorCurrencySpec: QuickSpec {
    override func spec() {

        describe("Calculator.parseCurrency") {

            it("parses simple integer amounts") {
                let result = Calculator.parseCurrency("15 usd thb")
                expect(result?.amount) == 15.0
                expect(result?.from) == "usd"
                expect(result?.to) == "thb"
            }

            it("parses decimal amounts") {
                let result = Calculator.parseCurrency("15.5 usd thb")
                expect(result?.amount) == 15.5
            }

            it("normalizes currency codes to lowercase") {
                let result = Calculator.parseCurrency("15 USD THB")
                expect(result?.from) == "usd"
                expect(result?.to) == "thb"
            }

            it("accepts 4-letter codes (e.g. xrpl, usdt)") {
                let result = Calculator.parseCurrency("1 usdt thb")
                expect(result?.from) == "usdt"
            }

            it("rejects nonsense") {
                expect(Calculator.parseCurrency("nonsense")).to(beNil())
                expect(Calculator.parseCurrency("15 thb")).to(beNil())
                expect(Calculator.parseCurrency("usd thb")).to(beNil())
            }
        }

        describe("Calculator.formatRate") {

            it("strips the decimal for integer values") {
                expect(Calculator.formatRate(15.0)) == "15"
            }

            it("uses %g for non-integer values") {
                expect(Calculator.formatRate(15.5)) == "15.5"
                expect(Calculator.formatRate(0.001)) == "0.001"
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add ClipyTests/AppLauncher/CalculatorCurrencySpec.swift
git commit -m "test Calculator currency parsing and rate formatting"
```

---

## Task 11: Calculator stateful surface — items, currency cache, fetch

**Files:**
- Modify: `Clipy/Sources/AppLauncher/Calculator.swift`

Direct port of selector's `currencyItems` / `kickOffFetch` / `readRate` plus the new `items(for:)` entry point that the launcher panel calls.

- [ ] **Step 1: Append to `Calculator.swift`**

Inside the existing `Calculator` class, add the instance-state members and the `items(for:)` method that the launcher panel will call. Source: `/Users/ank/dev/selector/selector/ShortcutCellView.swift:1280-1364`.

```swift
    // MARK: - Stateful currency cache + fetch

    private var pendingFetch: URLSessionDataTask?

    private var ratesDir: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.local/share/app-launcher/var/rates", isDirectory: true)
    }

    /// Returns math/currency rows for the launcher panel. `query` is the
    /// search text WITHOUT the trailing `=` (caller strips). Returns `[]`
    /// when the input doesn't look like a math or currency expression.
    func items(for rawQuery: String) -> [LauncherItem] {
        guard rawQuery.contains("=") else { return [] }

        // Cyrillic→Latin translit so `15 гыв ери=` becomes `15 usd thb=` first.
        let rewritten = AppIndex.translitCyrillicToLatin(rawQuery)
        let stripped = rewritten.replacingOccurrences(of: "=", with: "")
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = Calculator.parseCurrency(trimmed) {
            if let rows = currencyItems(amount: parsed.amount, from: parsed.from, to: parsed.to) {
                return rows
            }
            return [.status("fetching \(parsed.from.uppercased()) rates…")]
        }

        if trimmed.range(of: "[0-9]", options: .regularExpression) != nil,
           let result = Calculator.evaluateMath(trimmed) {
            return [
                .calcCopyResult(expression: trimmed, result: result),
                .calcCopyFull(expression: trimmed, result: result)
            ]
        }
        return []
    }

    /// Cancel any in-flight rate fetch — called from `AppLauncher.hide()`
    /// so a cancelled launcher session doesn't leave a wasted request.
    func cancelPendingFetch() {
        pendingFetch?.cancel()
        pendingFetch = nil
    }

    private func currencyItems(amount: Double, from: String, to: String) -> [LauncherItem]? {
        let file = ratesDir.appendingPathComponent("\(from).tsv")
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
        let stale = mtime == nil || Date().timeIntervalSince(mtime!) > 4 * 3600

        if stale { kickOffFetch(base: from) }

        if let rate = readRate(toCcy: to, from: file) {
            let result = amount * rate
            let formatted = result < 1
                ? String(format: "%.6f", result)
                : String(format: "%.2f", result)
            let expr = "\(Calculator.formatRate(amount)) \(from.uppercased())=\(formatted) \(to.uppercased())"
            return [
                .calcCopyResult(expression: expr,
                                result: "\(formatted) \(to.uppercased())"),
                .calcCopyFull(expression: expr,
                              result: "\(formatted) \(to.uppercased())")
            ]
        }
        return nil
    }

    private func readRate(toCcy to: String, from file: URL) -> Double? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2, parts[0] == to {
                return Double(parts[1])
            }
        }
        return nil
    }

    private func kickOffFetch(base: String) {
        pendingFetch?.cancel()
        let url = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/\(base).json")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self = self,
                  let data = data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json[base] as? [String: Any] else { return }
            var lines: [String] = []
            for (k, v) in rates {
                if let n = (v as? NSNumber)?.doubleValue {
                    lines.append("\(k)\t\(n)")
                }
            }
            let body = lines.joined(separator: "\n") + "\n"
            try? FileManager.default.createDirectory(at: self.ratesDir, withIntermediateDirectories: true)
            try? body.write(to: self.ratesDir.appendingPathComponent("\(base).tsv"),
                            atomically: true,
                            encoding: .utf8)
            DispatchQueue.main.async {
                AppLauncher.shared.rebuildDidFinish()
            }
        }
        pendingFetch = task
        task.resume()
    }
```

`LauncherItem` is forward-declared — it lives in `AppLauncher.swift` and is created in Task 13.

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppLauncher/Calculator.swift
git commit -m "add Calculator currency fetch and items"
```

---

## Task 12: `LauncherPanel.swift`

NSPanel subclass — Esc, ⌘C/V/X/A/Z forwarding, ⌘, → Clipy preferences. Source: `/Users/ank/dev/selector/selector/ShortcutCellView.swift:1384-1426`.

**Files:**
- Create: `Clipy/Sources/AppLauncher/LauncherPanel.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  LauncherPanel.swift
//
//  Clipy AppLauncher — NSPanel subclass for first-responder + key forwarding.
//

import Cocoa

/// NSPanel subclass that:
/// - becomes key (so the search field can have focus)
/// - forwards standard editing key-equivalents to the first responder
///   (LSUIElement apps don't ship a visible Edit menu, so ⌘C/V/X/A/Z
///   wouldn't fire for an NSSearchField inside our panel without this)
/// - closes on Esc
/// - on ⌘, hides itself and opens Clipy preferences
final class LauncherPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        AppLauncher.shared.hide()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let mods = event.modifierFlags.intersection(mask)
        if mods == .command, let chars = event.charactersIgnoringModifiers {
            if chars == "," {
                AppLauncher.shared.hide()
                CPYPreferencesWindowController.sharedController.showWindow(self)
                return true
            }
            let selector: Selector? = {
                switch chars {
                case "c": return #selector(NSText.copy(_:))
                case "v": return #selector(NSText.paste(_:))
                case "x": return #selector(NSText.cut(_:))
                case "a": return #selector(NSStandardKeyBindingResponding.selectAll(_:))
                case "z": return Selector(("undo:"))
                default:  return nil
                }
            }()
            if let sel = selector,
               let fr = firstResponder,
               fr.tryToPerform(sel, with: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
```

The key clipy-specific change vs selector: `MainWindowController.shared.showAndActivate(self)` → `CPYPreferencesWindowController.sharedController.showWindow(self)`.

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppLauncher/LauncherPanel.swift
git commit -m "add LauncherPanel for AppLauncher"
```

---

## Task 13: `AppLauncher.swift` — main panel class

Full port of selector's `AppLauncher` class, lines 659–1383 of `ShortcutCellView.swift`, **excluding the math/currency/translit/reload sections that already live in `AppIndex` and `Calculator`**.

This file owns: panel + searchField + tableView setup, show/hide, filter dispatch, NSTableView/NSSearchField delegates, activation, the `LauncherItem` enum, and the `rebuildDidFinish()` callback used by `AppIndex.buildIndexAsync` and `Calculator.kickOffFetch`.

**Files:**
- Create: `Clipy/Sources/AppLauncher/AppLauncher.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  AppLauncher.swift
//
//  Clipy AppLauncher — NSPanel + filter + dispatch.
//

import Cocoa

enum LauncherItem {
    case app(name: String, running: Bool)
    case calcCopyResult(expression: String, result: String)
    case calcCopyFull(expression: String, result: String)
    case status(String)
}

final class AppLauncher: NSObject, NSWindowDelegate, NSSearchFieldDelegate,
                         NSTableViewDataSource, NSTableViewDelegate {

    static let shared = AppLauncher()

    // MARK: - Storage

    private var panel: NSPanel?
    private var searchField: NSSearchField!
    private var tableView: NSTableView!

    private var visibleItems: [LauncherItem] = []
    private var runningApps: Set<String> = []
    private var lastQuery: String = ""

    private static let dotTag = 1001

    // MARK: - Hotkey entry points

    func toggle() {
        if let p = panel, p.isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Build the panel + warm caches off the critical path so the first
    /// hotkey press is as fast as every subsequent one. Called once from
    /// AppLauncherService.setup().
    func preload() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            if self.panel == nil { self.setupPanel() }
            AppIndex.shared.reloadIfNeeded()
            self.refreshRunningApps()
        }
    }

    func show() {
        if panel == nil { setupPanel() }
        guard let panel = panel, let searchField = searchField else { return }

        AppIndex.shared.reloadIfNeeded()
        refreshRunningApps()
        searchField.stringValue = ""
        lastQuery = ""
        applyFilter("")

        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 600, height: 480)
        let preferredHeight: CGFloat = 760
        let maxHeight = max(240, visible.height - 80)
        let targetHeight = min(preferredHeight, maxHeight)
        panel.setContentSize(NSSize(width: 600, height: targetHeight))

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        panel?.orderOut(nil)
        Calculator.shared.cancelPendingFetch()
    }

    /// Called from background workers (AppIndex async rebuild,
    /// Calculator currency fetch) when fresh data has just landed and the
    /// visible filter result needs to be redrawn.
    func rebuildDidFinish() {
        guard let panel = panel, panel.isVisible else { return }
        applyFilter(lastQuery)
    }

    private func refreshRunningApps() {
        var s: Set<String> = []
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular {
            if let name = app.localizedName { s.insert(name) }
        }
        runningApps = s
    }

    // MARK: - Panel setup

    private func setupPanel() {
        let p = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        p.title = "Clipy Launcher"
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self

        let content = NSView()

        let sf = NSSearchField()
        sf.delegate = self
        sf.placeholderString = "App, math (`(1+2)=`), or currency (`15 usd thb=`)"
        sf.font = NSFont.systemFont(ofSize: 16)
        sf.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sf)

        let tv = NSTableView()
        tv.dataSource = self
        tv.delegate = self
        tv.headerView = nil
        tv.rowHeight = 24
        tv.selectionHighlightStyle = .regular
        tv.style = .plain
        tv.intercellSpacing = NSSize(width: 0, height: 2)
        tv.target = self
        tv.action = #selector(rowClicked)
        tv.doubleAction = #selector(rowClicked)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.width = 580
        tv.addTableColumn(col)

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            sf.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            sf.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            sf.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            sf.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: sf.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])

        p.contentView = content
        self.panel = p
        self.searchField = sf
        self.tableView = tv
    }

    // MARK: - Filter

    private func applyFilter(_ rawQuery: String) {
        let q = rawQuery.precomposedStringWithCanonicalMapping
        lastQuery = q

        var items: [LauncherItem] = []
        items.append(contentsOf: Calculator.shared.items(for: q))
        for (name, running) in AppIndex.shared.match(query: q, runningNames: runningApps) {
            items.append(.app(name: name, running: running))
        }
        visibleItems = items

        tableView?.reloadData()
        if !visibleItems.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { visibleItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: self)
                    as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("cell")

        let dotLabel: NSTextField = (cell.viewWithTag(Self.dotTag) as? NSTextField) ?? {
            let d = NSTextField(labelWithString: "●")
            d.tag = Self.dotTag
            d.font = NSFont.systemFont(ofSize: 14)
            d.textColor = NSColor.systemGreen
            d.alignment = .right
            d.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(d)
            NSLayoutConstraint.activate([
                d.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                d.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                d.widthAnchor.constraint(equalToConstant: 16)
            ])
            return d
        }()

        let tf = cell.textField ?? {
            let f = NSTextField(labelWithString: "")
            f.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(f)
            cell.textField = f
            NSLayoutConstraint.activate([
                f.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                f.trailingAnchor.constraint(equalTo: dotLabel.leadingAnchor, constant: -6),
                f.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return f
        }()
        tf.font = NSFont.systemFont(ofSize: 14)
        tf.lineBreakMode = .byTruncatingTail
        tf.textColor = NSColor.labelColor

        switch visibleItems[row] {
        case .app(let name, let running):
            tf.stringValue = name
            dotLabel.isHidden = !running
        case .calcCopyResult(let expr, let result):
            tf.stringValue = "🧮 \(expr) = \(result)   (Enter to copy result)"
            dotLabel.isHidden = true
        case .calcCopyFull(let expr, let result):
            tf.stringValue = "📋 \(expr) = \(result)   (Enter to copy expression = result)"
            dotLabel.isHidden = true
        case .status(let msg):
            tf.stringValue = msg
            tf.textColor = .secondaryLabelColor
            dotLabel.isHidden = true
        }
        return cell
    }

    @objc private func rowClicked() {
        activateSelection()
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            activateSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !visibleItems.isEmpty else { return }
        let current = tableView.selectedRow
        var next = current + delta
        if next < 0 { next = 0 }
        if next >= visibleItems.count { next = visibleItems.count - 1 }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    // MARK: - Activation

    private func activateSelection() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard row < visibleItems.count else { hide(); return }
        let item = visibleItems[row]
        switch item {
        case .app(let name, _):
            hide()
            if let url = AppIndex.shared.resolveURL(named: name) {
                NSWorkspace.shared.openApplication(at: url,
                                                    configuration: NSWorkspace.OpenConfiguration(),
                                                    completionHandler: nil)
            }
        case .calcCopyResult(_, let result):
            copyToPasteboard(result)
            hide()
        case .calcCopyFull(let expr, let result):
            copyToPasteboard("\(expr) = \(result)")
            hide()
        case .status:
            break
        }
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        Calculator.shared.cancelPendingFetch()
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppLauncher/AppLauncher.swift
git commit -m "add AppLauncher panel, filter, and activation"
```

---

## Task 14: `AppLauncherService.swift` — Magnet hotkey wiring

This is the new layer that doesn't exist in selector — selector uses `MASShortcutBinder` over Carbon directly. In clipy we use Magnet, matching the existing `HotKeyService`.

**Files:**
- Create: `Clipy/Sources/AppLauncher/AppLauncherService.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  AppLauncherService.swift
//
//  Clipy AppLauncher — Magnet HotKey registration and lifecycle.
//

import Cocoa
import Magnet

final class AppLauncherService: NSObject {

    private static let identifier = "AppLauncherHotKey"
    private var keyCombo: KeyCombo?

    /// Called once from AppDelegate.applicationDidFinishLaunching. Pre-seeds
    /// the factory default ⌘Space if the user has never had a value
    /// archived (gated by Constants.HotKey.appLauncherDidPreSeed so a user
    /// who later clears the shortcut stays cleared).
    func setupHotKey() {
        let defaults = AppEnvironment.current.defaults
        if !defaults.bool(forKey: Constants.HotKey.appLauncherDidPreSeed) {
            // ⌘Space — see selector AppLauncherShortcut.factoryDefault
            // (kVK_Space = 49, cmdKey = 256 in Carbon parlance).
            if let combo = KeyCombo(QWERTYKeyCode: 49, carbonModifiers: 256),
               let data = combo.archive() as Data? {
                defaults.set(data, forKey: Constants.HotKey.appLauncherKeyCombo)
            }
            defaults.set(true, forKey: Constants.HotKey.appLauncherDidPreSeed)
        }
        change(keyCombo: savedKeyCombo())
        AppLauncher.shared.preload()
    }

    /// Re-register when the user edits the shortcut from preferences.
    func change(keyCombo: KeyCombo?) {
        self.keyCombo = keyCombo

        if let data = keyCombo?.archive() {
            AppEnvironment.current.defaults.set(data, forKey: Constants.HotKey.appLauncherKeyCombo)
        } else {
            AppEnvironment.current.defaults.removeObject(forKey: Constants.HotKey.appLauncherKeyCombo)
        }

        HotKeyCenter.shared.unregisterHotKey(with: AppLauncherService.identifier)
        guard let keyCombo = keyCombo else { return }

        let hotKey = HotKey(identifier: AppLauncherService.identifier,
                            keyCombo: keyCombo,
                            target: self,
                            action: #selector(handleHotKey))
        if !hotKey.register() {
            NSLog("AppLauncherService: failed to register hotkey \(keyCombo)")
        }
    }

    /// Convenience accessor for the preferences UI.
    var currentKeyCombo: KeyCombo? { keyCombo }

    @objc private func handleHotKey() {
        DispatchQueue.main.async {
            AppLauncher.shared.toggle()
        }
    }

    private func savedKeyCombo() -> KeyCombo? {
        guard let data = AppEnvironment.current.defaults.data(forKey: Constants.HotKey.appLauncherKeyCombo) else {
            return nil
        }
        return KeyCombo.unarchive(with: data)
    }
}
```

The KeyCombo `archive()` and `KeyCombo.unarchive(with:)` calls match the patterns in `Clipy/Sources/Services/HotKeyService.swift` (verify by grepping the file if signatures differ).

- [ ] **Step 2: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppLauncher/AppLauncherService.swift
git commit -m "add AppLauncherService Magnet hotkey wiring"
```

---

## Task 15: Wire `AppLauncherService` into `Environment` and `AppEnvironment`

**Files:**
- Modify: `Clipy/Sources/Environments/Environment.swift`
- Modify: `Clipy/Sources/Environments/AppEnvironment.swift`

- [ ] **Step 1: Add the property and init param to `Environment`**

Open `Clipy/Sources/Environments/Environment.swift`. Add `appLauncherService` to the property list, init signature, and assignment block:

```swift
struct Environment {

    // MARK: - Properties
    let clipService: ClipService
    let hotKeyService: HotKeyService
    let dataCleanService: DataCleanService
    let pasteService: PasteService
    let excludeAppService: ExcludeAppService
    let accessibilityService: AccessibilityService
    let updateService: UpdateService
    let menuManager: MenuManager
    let appLauncherService: AppLauncherService

    let defaults: UserDefaults

    // MARK: - Initialize
    init(clipService: ClipService = ClipService(),
         hotKeyService: HotKeyService = HotKeyService(),
         dataCleanService: DataCleanService = DataCleanService(),
         pasteService: PasteService = PasteService(),
         excludeAppService: ExcludeAppService = ExcludeAppService(applications: []),
         accessibilityService: AccessibilityService = AccessibilityService(),
         updateService: UpdateService = UpdateService(),
         menuManager: MenuManager = MenuManager(),
         appLauncherService: AppLauncherService = AppLauncherService(),
         defaults: UserDefaults = .standard) {

        self.clipService = clipService
        self.hotKeyService = hotKeyService
        self.dataCleanService = dataCleanService
        self.pasteService = pasteService
        self.excludeAppService = excludeAppService
        self.accessibilityService = accessibilityService
        self.updateService = updateService
        self.menuManager = menuManager
        self.appLauncherService = appLauncherService
        self.defaults = defaults
    }
}
```

- [ ] **Step 2: Update `AppEnvironment.replaceCurrent` to thread the new service**

Open `Clipy/Sources/Environments/AppEnvironment.swift`. The `replaceCurrent(...)` static func has explicit parameters for every service. Add `appLauncherService: AppLauncherService = current.appLauncherService,` to its signature and pass it through to the `Environment(...)` init. Same change in `fromStorage`:

```swift
static func replaceCurrent(clipService: ClipService = current.clipService,
                           hotKeyService: HotKeyService = current.hotKeyService,
                           dataCleanService: DataCleanService = current.dataCleanService,
                           pasteService: PasteService = current.pasteService,
                           excludeAppService: ExcludeAppService = current.excludeAppService,
                           accessibilityService: AccessibilityService = current.accessibilityService,
                           updateService: UpdateService = current.updateService,
                           menuManager: MenuManager = current.menuManager,
                           appLauncherService: AppLauncherService = current.appLauncherService,
                           defaults: UserDefaults = current.defaults) {
    replaceCurrent(environment: Environment(clipService: clipService,
                                            hotKeyService: hotKeyService,
                                            dataCleanService: dataCleanService,
                                            pasteService: pasteService,
                                            excludeAppService: excludeAppService,
                                            accessibilityService: accessibilityService,
                                            updateService: updateService,
                                            menuManager: menuManager,
                                            appLauncherService: appLauncherService,
                                            defaults: defaults))
}
```

In `fromStorage(...)`, add the same pass-through to its `Environment(...)` call.

- [ ] **Step 3: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/Environments/Environment.swift Clipy/Sources/Environments/AppEnvironment.swift
git commit -m "wire AppLauncherService into AppEnvironment"
```

---

## Task 16: Add new files to Xcode project (Clipy + ClipyTests targets)

This task uses the `xcodeproj` Ruby gem to add the source and test files we created in Tasks 4–14 to their respective Xcode targets. Without this step, none of the new code compiles into the app or test bundles.

**Files:**
- Modify: `Clipy.xcodeproj/project.pbxproj` (via Ruby script)

- [ ] **Step 1: Ensure `xcodeproj` gem is available**

```bash
gem list -i xcodeproj 2>/dev/null || gem install --user-install xcodeproj
ruby -rxcodeproj -e 'puts "ok"'
```

Expected: `ok`. If `gem install` fails on permissions, retry with `sudo gem install xcodeproj` and inform the user.

- [ ] **Step 2: Run the project mutation script**

```bash
cd /Volumes/dev/code-dev/clipy
ruby <<'RUBY'
require "xcodeproj"

project = Xcodeproj::Project.open("Clipy.xcodeproj")

clipy_target = project.targets.find { |t| t.name == "Clipy" }
test_target  = project.targets.find { |t| t.name == "ClipyTests" }
abort "Clipy target not found"     unless clipy_target
abort "ClipyTests target not found" unless test_target

# Sources/AppLauncher group
sources_group = project.main_group["Clipy"]["Sources"]
abort "Sources group not found" unless sources_group
launcher_group = sources_group["AppLauncher"] || sources_group.new_group("AppLauncher", "AppLauncher")

source_files = %w[
  AppIndex.swift
  Calculator.swift
  LauncherPanel.swift
  AppLauncher.swift
  AppLauncherService.swift
]
source_files.each do |fname|
  next if launcher_group.files.any? { |f| f.path == fname }
  ref = launcher_group.new_reference(fname)
  clipy_target.source_build_phase.add_file_reference(ref)
end

# ClipyTests/AppLauncher group
tests_group = project.main_group["ClipyTests"]
abort "ClipyTests group not found" unless tests_group
test_launcher_group = tests_group["AppLauncher"] || tests_group.new_group("AppLauncher", "AppLauncher")

test_files = %w[
  AppIndexTranslitSpec.swift
  AppIndexFilterSpec.swift
  CalculatorMathSpec.swift
  CalculatorCurrencySpec.swift
]
test_files.each do |fname|
  next if test_launcher_group.files.any? { |f| f.path == fname }
  ref = test_launcher_group.new_reference(fname)
  test_target.source_build_phase.add_file_reference(ref)
end

project.save
puts "Added #{source_files.size} sources to Clipy and #{test_files.size} specs to ClipyTests."
RUBY
```

Expected stdout: `Added 5 sources to Clipy and 4 specs to ClipyTests.`

The script is idempotent — running it again is a no-op.

- [ ] **Step 3: Build to verify the new files compile**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -8
```

Expected: `** BUILD SUCCEEDED **`. If failures appear, read the error: a likely culprit is the `KeyCombo.unarchive(with:)` API in `AppLauncherService` not matching clipy's Magnet version. Fix any signature mismatch by grepping `Clipy/Sources/Services/HotKeyService.swift` for the actual call shape used there and mirroring it.

- [ ] **Step 4: Run tests**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace Clipy.xcworkspace -scheme Clipy -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -15
```

Expected: all 4 new spec files run, all `it` blocks pass, no regressions in existing tests. If any test fails, fix the implementation (NOT the test) and re-run.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy.xcodeproj/project.pbxproj
git commit -m "register AppLauncher sources and specs in xcode project"
```

---

## Task 17: Bootstrap `AppLauncherService` from `applicationDidFinishLaunching`

**Files:**
- Modify: `Clipy/Sources/AppDelegate.swift:303` (in `applicationDidFinishLaunching`, near line 327 where `setupDefaultHotKeys` is called)

- [ ] **Step 1: Find the right insertion point**

```bash
cd /Volumes/dev/code-dev/clipy
grep -n "setupDefaultHotKeys" Clipy/Sources/AppDelegate.swift
```

Expected: a single hit — the line currently reading `AppEnvironment.current.hotKeyService.setupDefaultHotKeys()` in `applicationDidFinishLaunching`.

- [ ] **Step 2: Add the launcher bootstrap right after it**

Open `Clipy/Sources/AppDelegate.swift`. After `AppEnvironment.current.hotKeyService.setupDefaultHotKeys()`, add a new line:

```swift
        AppEnvironment.current.hotKeyService.setupDefaultHotKeys()
        AppEnvironment.current.appLauncherService.setupHotKey()
```

- [ ] **Step 3: Build**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/AppDelegate.swift
git commit -m "bootstrap AppLauncherService at launch"
```

---

## Task 18: Add 5th RecordView outlet + handler in `CPYShortcutsPreferenceViewController.swift`

**Files:**
- Modify: `Clipy/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift`

- [ ] **Step 1: Add the outlet, prepare-load, and recording handler**

Replace the four-outlet block:

```swift
    @IBOutlet private weak var mainShortcutRecordView: RecordView!
    @IBOutlet private weak var historyShortcutRecordView: RecordView!
    @IBOutlet private weak var snippetShortcutRecordView: RecordView!
    @IBOutlet private weak var clearHistoryShortcutRecordView: RecordView!
```

with five:

```swift
    @IBOutlet private weak var mainShortcutRecordView: RecordView!
    @IBOutlet private weak var historyShortcutRecordView: RecordView!
    @IBOutlet private weak var snippetShortcutRecordView: RecordView!
    @IBOutlet private weak var clearHistoryShortcutRecordView: RecordView!
    @IBOutlet private weak var appLauncherShortcutRecordView: RecordView!
```

In `loadView()`, after `clearHistoryShortcutRecordView.delegate = self`, add:

```swift
        appLauncherShortcutRecordView.delegate = self
```

In `prepareHotKeys()`, after `clearHistoryShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.clearHistoryKeyCombo`, add:

```swift
        appLauncherShortcutRecordView.keyCombo = AppEnvironment.current.appLauncherService.currentKeyCombo
```

In the `didChangeKeyCombo` switch, after the `clearHistoryShortcutRecordView` case, add:

```swift
        case appLauncherShortcutRecordView:
            AppEnvironment.current.appLauncherService.change(keyCombo: keyCombo)
```

- [ ] **Step 2: Commit (XIB still has only 4 rows — that's Task 19)**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/Preferences/Panels/CPYShortcutsPreferenceViewController.swift
git commit -m "add app launcher row to shortcuts preferences view controller"
```

The Swift file references an outlet that the XIB does not yet bind. Building will succeed (the `!` IUO is silent at compile time) but the outlet will be `nil` at runtime until Task 19 wires it. Don't open Preferences → Shortcuts between this commit and the next.

---

## Task 19: Add 5th row to `CPYShortcutsPreferenceViewController.xib`

This is the only XIB edit in the plan. It is small but tedious. Two acceptable approaches:

**Approach A (recommended): edit in Xcode by hand.** The agent (or user) opens Xcode, edits the XIB, saves, commits. XIBs are XML but editing them blind is error-prone — Xcode is the right tool.

**Approach B (no Xcode): edit the XML directly.** Risky; only do this if Xcode is unavailable. The XIB lives at `Clipy/Sources/Preferences/Panels/Base.lproj/CPYShortcutsPreferenceViewController.xib`.

**Files:**
- Modify: `Clipy/Sources/Preferences/Panels/Base.lproj/CPYShortcutsPreferenceViewController.xib`

- [ ] **Step 1 (Approach A): Open the XIB in Xcode**

```bash
open /Volumes/dev/code-dev/clipy/Clipy.xcworkspace
```

In Project Navigator: **Clipy → Sources → Preferences → Panels → Base.lproj → CPYShortcutsPreferenceViewController.xib**.

- [ ] **Step 2: Duplicate the "Clear History" row**

Select the `NSTextField` "Clear History:" label and the `RecordView` next to it. ⌘C, ⌘V. Reposition the duplicates below the originals (use the same vertical spacing as between existing rows; usually 30pt).

Change the new label's text to `App Launcher:` (or `Лаунчер` if you want localization — see `.github/CONTRIBUTING.md` for the localization convention; English in the base XIB is the project standard).

Resize the parent view if needed so all 5 rows fit without clipping.

- [ ] **Step 3: Bind the new RecordView to `appLauncherShortcutRecordView`**

Select the new `RecordView`. Open the Connections inspector (⌥⌘6). Drag from `New Referencing Outlet` to **File's Owner** → `appLauncherShortcutRecordView`.

Save (⌘S).

- [ ] **Step 4: Build and smoke-test the preferences pane**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace Clipy.xcworkspace -scheme Clipy -configuration Release \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/dev/code-dev/clipy
git add Clipy/Sources/Preferences/Panels/Base.lproj/CPYShortcutsPreferenceViewController.xib
git commit -m "add app launcher row to shortcuts preferences xib"
```

---

## Task 20: Run full test suite

**Files:** none (verification only)

- [ ] **Step 1: Run all tests**

```bash
cd /Volumes/dev/code-dev/clipy
xcodebuild \
  -workspace Clipy.xcworkspace -scheme Clipy -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`. All four new specs pass alongside existing ones.

If failures appear in the new specs, fix them before proceeding. If failures appear in existing specs, investigate — the port should not affect them. Most likely culprit if existing tests fail: a typo in an `AppEnvironment` property accessor that the existing test suite happens to exercise.

---

## Task 21: Manual smoke test against the running app

**Files:** none (verification only)

- [ ] **Step 1: Stop any running selector or clipy instance**

```bash
pkill -x Selector 2>/dev/null
pkill -x Clipy 2>/dev/null
sleep 1
```

- [ ] **Step 2: Replace `/Applications/Clipy.app` with the fresh build**

```bash
rm -rf /Applications/Clipy.app
cp -R /Volumes/dev/code-dev/clipy/build/DerivedData/Build/Products/Release/Clipy.app /Applications/Clipy.app
open /Applications/Clipy.app
```

- [ ] **Step 3: Verify Clipy is running**

```bash
pgrep -lx Clipy
```

Expected: a single line with PID and `Clipy`.

- [ ] **Step 4: Manual verification checklist**

Test each scenario by hand:

| # | Action | Expected |
|---|--------|----------|
| 1 | Press ⌘Space | Launcher panel opens centered, search field focused |
| 2 | Type `term` | Terminal.app appears at top of list, with `●` if running |
| 3 | Type `ьфшд` (Russian-layout `Mail`) | Mail.app matches |
| 4 | Type `ЬФШД` (uppercase Cyrillic) | Mail.app still matches (case-insensitive) |
| 5 | Press ↓ then Enter on Mail | Mail launches; panel closes |
| 6 | Reopen with ⌘Space; type `(1+2)*3=` | Two 🧮/📋 rows appear with `9` |
| 7 | Press Enter on the 🧮 row | `9` is in the clipboard (paste somewhere to confirm) |
| 8 | Reopen; type `15 usd thb=` | First time: `fetching USD rates…`. Within ~1s rows appear |
| 9 | Press Enter on the result row | Formatted result is in the clipboard |
| 10 | Press ⌘, inside the panel | Panel closes; Clipy preferences window opens |
| 11 | Preferences → Shortcuts tab | Five rows visible; "App Launcher" shows ⌘Space |
| 12 | Click the App Launcher record view, type ⌘⌥G | Shortcut updates; ⌘Space stops working; ⌘⌥G opens panel |
| 13 | Reset back to ⌘Space via the same record view | ⌘Space working again |
| 14 | Delete a `.app` from `/Applications` (e.g. via Finder Trash) | Reopen launcher within 1s; entry gone (worst case 200ms) |
| 15 | Apps in `/Applications/Utilities/` | e.g. `terminal` finds Terminal.app at `/System/Applications/Utilities/Terminal.app`, click launches it (no silent failure) |

If any row fails, fix the underlying code, rebuild, replace `/Applications/Clipy.app`, retest. Do not move to Task 22 until all 15 checks pass.

---

## Task 22: Decommission Selector

**Files:** none (filesystem cleanup)

- [ ] **Step 1: Confirm clipy is responsible for ⌘Space**

```bash
pgrep -lx Clipy
pgrep -lx Selector
```

Expected: Clipy running, Selector NOT running.

- [ ] **Step 2: Remove `/Applications/Selector.app`**

```bash
rm -rf /Applications/Selector.app
ls /Applications/Selector.app 2>&1
```

Expected: `No such file or directory`.

- [ ] **Step 3: Remove Selector from Login Items if present**

This is a manual step in **System Settings → General → Login Items**. Delete any "Selector" entry. The user does this themselves; no automation here.

- [ ] **Step 4: Final smoke test**

Press ⌘Space — launcher should still work, served by Clipy. Confirm by checking process owner:

```bash
osascript -e 'tell application "System Events" to get name of (first process whose frontmost is true)' &
sleep 1
# Manually press ⌘Space — verify the Clipy launcher panel appears, not Spotlight or any other app
```

- [ ] **Step 5: Final commit (none needed — no source changes; just close out the plan)**

There is no commit for this task. The migration is filesystem-only. The implementation is complete.

---

## Self-review notes (filled in after writing the plan)

**Spec coverage:**
- Goal / single-process unification → Task 22 + bootstrap in Task 17.
- A (apps), B (math), C (currency) → Tasks 4, 7, 8, 11, 13.
- 5 files in `AppLauncher/` → Tasks 4, 7, 8, 11, 12, 13, 14.
- `NetworkIsolation` exception → Task 3.
- Magnet hotkey wiring + preferences integration → Tasks 14, 15, 17, 18, 19.
- Constants + pre-seed → Tasks 2 and 14 (pre-seed lives in `AppLauncherService.setupHotKey`, single location, matches updated spec section).
- Cache paths under `~/.local/share/app-launcher/var/` → Task 7 (`cacheDir`/`appsFile`) and Task 11 (`ratesDir`).
- Quick/Nimble specs → Tasks 5, 6, 9, 10.
- Migration → Task 22.

**Placeholder scan:** none. Every code step shows the actual code. Where verbatim-from-selector ports are involved, the source line range is cited so the engineer can cross-reference.

**Type consistency:** `AppEntry`, `LauncherItem`, `AppLauncherService.identifier`, `Constants.HotKey.appLauncherKeyCombo`, `appLauncherService` property name — all consistent across tasks.

**Risks called out for execution:**
- Task 16 may reveal a `KeyCombo` API mismatch with clipy's Magnet version. Mitigation noted in step 3.
- Task 19 (XIB edit) is the only step that's awkward to automate. Approach A (Xcode hands-on) is the recommended path; Approach B (XML edit) is a fallback.
- Task 18→19 has a window where the build succeeds but a runtime nil outlet would crash if Preferences → Shortcuts is opened. Noted in Task 18 commit message.
