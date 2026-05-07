//
//  Calculator.swift
//
//  Clipy AppLauncher — math evaluator + currency conversion.
//

// swiftlint:disable identifier_name

import Foundation

// Inputs come from the AppLauncher panel (main thread). Internal
// currency-fetch network call hops to a URLSession callback on a private
// queue, then dispatches results back to main before mutating cache.
// @unchecked Sendable preserves that discipline under Swift 6 strict mode.
final class Calculator: @unchecked Sendable {

    static let shared = Calculator()

    // MARK: - Cached regexes
    //
    // Compiled once at first use. Each `evaluateMath` / `parseCurrency`
    // call would otherwise rebuild these for no reason.

    private static let sqrtRegex = try! NSRegularExpression(pattern: #"sqrt\s*\(([^()]*)\)"#)
    private static let intPromoteRegex = try! NSRegularExpression(pattern: #"(?<![\d.])\d+(?![\d.])"#)
    private static let currencyRegex = try! NSRegularExpression(
        pattern: #"^\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]{3,4})\s*([a-zA-Z]{3,4})\s*$"#
    )

    // MARK: - Math (pure)

    static func evaluateMath(_ expr: String) -> String? {
        var normalized = expr
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "^", with: "**")
        while let m = sqrtRegex.firstMatch(in: normalized,
                                           range: NSRange(normalized.startIndex..<normalized.endIndex,
                                                          in: normalized)),
              let full = Range(m.range(at: 0), in: normalized),
              let arg = Range(m.range(at: 1), in: normalized) {
            normalized.replaceSubrange(full, with: "((\(normalized[arg]))**0.5)")
        }
        // Promote bare integer literals to doubles so NSExpression performs
        // floating-point division (otherwise "10/4" yields 2 instead of 2.5).
        let promoteRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        normalized = intPromoteRegex.stringByReplacingMatches(in: normalized,
                                                              range: promoteRange,
                                                              withTemplate: "$0.0")
        // Reject syntactically invalid input *before* NSExpression — its
        // `init(format:)` raises an Objective-C exception (uncatchable from
        // Swift) on malformed input like "1+", "(5", "*5", "1+*2".
        guard isValidExpression(normalized) else { return nil }
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

    /// Cheap syntactic check used as a pre-filter for `NSExpression(format:)`.
    /// Operates on the post-transform string (sqrt expanded, ^→**, ints promoted).
    /// Goal: reject anything that would raise an Objective-C exception inside
    /// NSExpression — partial expressions like "1+", trailing ops, unbalanced
    /// parens, doubled binary ops (except "**"), op adjacent to ")".
    static func isValidExpression(_ s: String) -> Bool {
        let stripped = s.replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "**", with: "^")
        guard !stripped.isEmpty else { return false }
        let chars = Array(stripped)
        let binary: Set<Character> = ["+", "-", "*", "/", "^"]
        let allowed: Set<Character> = ["(", ")", ".", "+", "-", "*", "/", "^"]
        for ch in chars {
            guard ch.isNumber || allowed.contains(ch) else { return false }
        }
        guard let first = chars.first else { return false }
        if first == ")" || first == "*" || first == "/" || first == "^" { return false }
        guard let last = chars.last, last.isNumber || last == "." || last == ")" else { return false }
        var depth = 0
        for ch in chars {
            if ch == "(" { depth += 1 } else if ch == ")" {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        guard depth == 0 else { return false }
        for i in 0..<(chars.count - 1) {
            let a = chars[i], b = chars[i + 1]
            // op + op: only "binary then unary +/-" is allowed (e.g. "5*-3").
            if binary.contains(a) && binary.contains(b) && b != "+" && b != "-" {
                return false
            }
            // "(" followed by binary op other than unary +/-.
            if a == "(" && binary.contains(b) && b != "+" && b != "-" { return false }
            // Empty pair of parens.
            if a == "(" && b == ")" { return false }
            // ")(" — implicit multiplication not supported by NSExpression.
            if a == ")" && b == "(" { return false }
            // Binary op immediately before ")".
            if binary.contains(a) && b == ")" { return false }
        }
        return true
    }

    // MARK: - Currency parsing (pure)

    // swiftlint:disable:next large_tuple
    static func parseCurrency(_ s: String) -> (amount: Double, from: String, to: String)? {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = currencyRegex.firstMatch(in: s, range: range), m.numberOfRanges == 4,
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

    // MARK: - Stateful currency cache + fetch

    private var pendingFetch: URLSessionDataTask?
    /// Per-base "don't retry until" timestamps. Prevents a request storm when
    /// the upstream rate API is down — without it, every keystroke through the
    /// debounce would fire a brand-new fetch (the rate file stays missing, so
    /// `stale` keeps evaluating true).
    private var failedFetchUntil: [String: Date] = [:]
    private static let failBackoff: TimeInterval = 60

    private var ratesDir: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.local/share/app-launcher/var/rates", isDirectory: true)
    }

    /// Returns math/currency rows for the launcher panel. `query` is the
    /// search text; rows are returned only when it contains `=`.
    func items(for rawQuery: String) -> [LauncherItem] {
        guard rawQuery.contains("=") else { return [] }

        // Cyrillic→Latin translit so `15 гыв ери=` becomes `15 usd thb=`.
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
    /// so a cancelled session doesn't leave a wasted request running.
    func cancelPendingFetch() {
        pendingFetch?.cancel()
        pendingFetch = nil
    }

    private func currencyItems(amount: Double, from: String, to: String) -> [LauncherItem]? {
        let file = ratesDir.appendingPathComponent("\(from).tsv")
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
        let stale = mtime == nil || Date().timeIntervalSince(mtime!) > 4 * 3600

        if stale {
            let backoffActive = (failedFetchUntil[from] ?? .distantPast) > Date()
            if !backoffActive { kickOffFetch(base: from) }
        }

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
            // Decide success up front so the deferred main-thread block can
            // both clear pendingFetch / record fail backoff *and* refresh the
            // panel — otherwise the launcher would stay stuck on the
            // "fetching … rates…" status row indefinitely on HTTP error.
            let success: Bool = {
                guard let data = data,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rates = json[base] as? [String: Any],
                      let self = self else { return false }
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
                return true
            }()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.pendingFetch = nil
                if success {
                    self.failedFetchUntil.removeValue(forKey: base)
                } else {
                    self.failedFetchUntil[base] = Date().addingTimeInterval(Calculator.failBackoff)
                }
                AppLauncher.shared.rebuildDidFinish()
            }
        }
        pendingFetch = task
        task.resume()
    }
}
