//
//  AppIndex.swift
//
//  Clipy AppLauncher — application discovery, cache, and matching.
//

// swiftlint:disable identifier_name

import Foundation

struct AppEntry {
    let original: String
    /// `original.lowercased()` precomputed once at load. Saves an allocation
    /// per app per filter pass — for ~500 apps × 10 keystrokes/sec = 5k
    /// fewer string allocations per second.
    let originalLowercased: String
    let cyr: String
    let lat: String
}

// Source of all installed-app names. Maintains a cached `apps.txt` index
// shared with the bash CLI `a` (path under `~/.local/share/app-launcher/var/`).
// All public reads/writes happen on the main thread (Preferences UI +
// AppLauncher panel). Internal background scans funnel results back to
// main before mutating shared state. @unchecked Sendable matches what
// the existing dispatch discipline already guarantees.
final class AppIndex: @unchecked Sendable {

    static let shared = AppIndex()

    /// Single source of truth for application source directories. `scanDepth`
    /// matches the recursion limit the scanner uses: user-visible roots can
    /// contain `Utilities/`, `Setapp/`, etc. (depth 3); CoreServices only
    /// needs Finder.app at depth 1.
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
        return entry.originalLowercased.contains(qlc)
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

    // MARK: - Stateful storage

    private var apps: [AppEntry] = []
    private var appsLoadedMtime: Date?
    private var indexBuildInFlight = false

    private var cacheDir: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.local/share/app-launcher/var", isDirectory: true)
    }
    private var appsFile: URL { cacheDir.appendingPathComponent("apps.txt") }

    /// Returns matching app entries. Running apps appear first.
    /// Caller passes the set of currently-running app names so the launcher
    /// UI can decorate them with the green ● dot.
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
                    let original = String(parts[0])
                    loaded.append(AppEntry(original: original,
                                           originalLowercased: original.lowercased(),
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
        var names = Set<String>()
        for (root, maxDepth) in AppIndex.appSourceRoots {
            names.formUnion(AppIndex.collectAppNames(at: root, maxDepth: maxDepth))
        }
        return Array(names).sorted()
    }

    /// Names of `.app` bundles under `root`, up to `maxDepth` levels deep.
    /// Combines the recursive URL enumerator with a top-level
    /// `contentsOfDirectory(atPath:)` pass: on recent macOS the URL
    /// enumerator silently drops `/Applications/Safari.app` because it is
    /// a symlink into `/System/Cryptexes/` and resource-value fetch fails
    /// on the cryptex target. The supplemental pass restores it.
    static func collectAppNames(at root: String, maxDepth: Int, fileManager fm: FileManager = .default) -> Set<String> {
        var names = Set<String>()
        if let en = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
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
        if let entries = try? fm.contentsOfDirectory(atPath: root) {
            for entry in entries where entry.hasSuffix(".app") {
                names.insert(String(entry.dropLast(4)))
            }
        }
        return names
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
}
