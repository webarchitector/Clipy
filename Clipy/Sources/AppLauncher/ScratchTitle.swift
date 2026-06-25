import Foundation

enum ScratchTitle {
    static func title(from content: String, maxLength: Int = 60) -> String {
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                if line.count > maxLength {
                    return String(line.prefix(maxLength)) + "…"
                }
                return line
            }
        }
        return ""
    }
}
