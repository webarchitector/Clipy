import Foundation

enum LauncherItems {
    static func withScratchpad(prefixing items: [LauncherItem],
                               query: String,
                               noteCount: Int) -> [LauncherItem] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        return [.scratchpad(noteCount: noteCount)] + items
    }
}
