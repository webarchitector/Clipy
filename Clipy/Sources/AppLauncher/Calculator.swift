//
//  Calculator.swift
//
//  Clipy AppLauncher — math evaluator + currency conversion.
//

// swiftlint:disable identifier_name

import Foundation

final class Calculator {

    static let shared = Calculator()

    // MARK: - Math (pure)

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

    // MARK: - Currency parsing (pure)

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

    // MARK: - Stateful currency cache + fetch

    private var pendingFetch: URLSessionDataTask?

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
}
