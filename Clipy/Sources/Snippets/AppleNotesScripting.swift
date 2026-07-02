import Foundation

protocol AppleNotesScripting: Sendable {
    func listFolderNames() throws -> [String]
    func fetchFolder(named name: String) throws -> NotesFolderNode
    func revealFolder(named name: String) throws
}

enum NotesOutputParser {
    private static let recordSeparator = "\u{1D}"
    private static let fieldSeparator = "\u{1E}"
    private static let pathSeparator = "\u{1F}"

    static func parseFolderNames(_ raw: String) -> [String] {
        return raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func parseNotes(_ raw: String, folderName: String) -> NotesFolderNode {
        let snippets: [NotesSnippetNode] = raw
            .components(separatedBy: recordSeparator)
            .filter { !$0.isEmpty }
            .map { record in
                let parts = record.components(separatedBy: fieldSeparator)
                let title = parts.first ?? ""
                let content = parts.count > 1 ? parts[1] : ""
                return NotesSnippetNode(title: title, content: content)
            }
        return NotesFolderNode(title: folderName, snippets: snippets, subfolders: [])
    }

    /// Parse the tree-format output from the recursive AppleScript.
    ///
    /// Separators: record = U+001D, field = U+001E, path-component = U+001F.
    ///
    /// Record types:
    /// - Folder: `"F"` + field + `<path>` where path components are root-inclusive,
    ///   joined by U+001F (e.g. "Root" or "Root\u{1F}Sub").
    /// - Note:   `"N"` + field + `<parentPath>` + field + `<title>` + field + `<content>`.
    ///
    /// Rules: unknown record kinds are ignored; intermediate folder nodes are
    /// created on demand; encounter order is preserved; the returned root node's
    /// title is always `rootFolderName`.
    static func parseTree(_ raw: String, rootFolderName: String) -> NotesFolderNode {
        let rs = recordSeparator
        let fs = fieldSeparator
        let ps = pathSeparator

        // Mutable builder node — used only within this function.
        final class MutableFolder {
            let title: String
            var snippets: [NotesSnippetNode] = []
            var subfolders: [MutableFolder] = []

            init(title: String) { self.title = title }
        }

        let root = MutableFolder(title: rootFolderName)
        // Key: path components joined by ps (e.g. "Root" or "Root\u{1F}Sub").
        var nodeByPath: [String: MutableFolder] = [rootFolderName: root]

        // Ensures every prefix folder in `pathComponents` exists and returns the
        // deepest node.  Maps any root name found in the data to `root` so that
        // minor name-case differences between `rootFolderName` and the AppleScript
        // output do not break the tree.
        func ensure(pathComponents: [String]) -> MutableFolder? {
            guard !pathComponents.isEmpty else { return nil }
            let rootKey = pathComponents[0]
            if nodeByPath[rootKey] == nil {
                nodeByPath[rootKey] = root
            }
            var current = root
            for i in 1..<pathComponents.count {
                let key = pathComponents[0...i].joined(separator: ps)
                if let existing = nodeByPath[key] {
                    current = existing
                } else {
                    let newNode = MutableFolder(title: pathComponents[i])
                    current.subfolders.append(newNode)
                    nodeByPath[key] = newNode
                    current = newNode
                }
            }
            return current
        }

        for record in raw.components(separatedBy: rs) where !record.isEmpty {
            let parts = record.components(separatedBy: fs)
            guard let kind = parts.first, !kind.isEmpty else { continue }
            if kind == "F", parts.count >= 2 {
                let pathComponents = parts[1].components(separatedBy: ps)
                _ = ensure(pathComponents: pathComponents)
            } else if kind == "N", parts.count >= 4 {
                let pathComponents = parts[1].components(separatedBy: ps)
                let title = parts[2]
                // Join tail fields with fs so content containing fs is preserved.
                let content = parts[3...].joined(separator: fs)
                if let folder = ensure(pathComponents: pathComponents) {
                    folder.snippets.append(NotesSnippetNode(title: title, content: content))
                }
            }
        }

        func toStruct(_ node: MutableFolder) -> NotesFolderNode {
            NotesFolderNode(
                title: node.title,
                snippets: node.snippets,
                subfolders: node.subfolders.map(toStruct)
            )
        }

        return toStruct(root)
    }
}

struct AppleScriptNotesScripting: AppleNotesScripting {
    private static let recordSeparator = "\u{1D}"
    private static let fieldSeparator = "\u{1E}"
    private static let pathSeparator = "\u{1F}"

    func listFolderNames() throws -> [String] {
        let source = """
        tell application "Notes"
            set out to ""
            repeat with f in folders
                set out to out & (name of f) & linefeed
            end repeat
            return out
        end tell
        """
        return NotesOutputParser.parseFolderNames(try run(source))
    }

    func fetchFolder(named name: String) throws -> NotesFolderNode {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        let rs = Self.recordSeparator
        let fs = Self.fieldSeparator
        let ps = Self.pathSeparator
        // Recursive script: emits F records (folder path) and N records (note data)
        // for the chosen folder and every subfolder, depth-first.
        //
        // Degradation: the subfolder enumeration (`folders of aFolder`) is wrapped
        // in `try` inside the handler so that macOS/Notes versions that do not
        // support nested-folder access gracefully fall back to flat behaviour —
        // the root F record and all root notes are always emitted before the try.
        let source = """
        tell application "Notes"
            set theFolder to first folder whose name is "\(escaped)"
            set rootName to name of theFolder
            set out to my collectFolder(theFolder, rootName)
            return out
        end tell

        on collectFolder(aFolder, folderPath)
            tell application "Notes"
                set out to "F" & "\(fs)" & folderPath & "\(rs)"
                repeat with n in notes of aFolder
                    set out to out & "N" & "\(fs)" & folderPath & "\(fs)" & (name of n) & "\(fs)" & (plaintext of n) & "\(rs)"
                end repeat
                try
                    repeat with sf in folders of aFolder
                        set sfPath to folderPath & "\(ps)" & (name of sf)
                        set out to out & my collectFolder(sf, sfPath)
                    end repeat
                end try
                return out
            end tell
        end collectFolder
        """
        return NotesOutputParser.parseTree(try run(source), rootFolderName: name)
    }

    func revealFolder(named name: String) throws {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Notes"
            activate
            show (first folder whose name is "\(escaped)")
        end tell
        """
        _ = try run(source)
    }

    private func run(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AppleNotesError.scriptFailed("could not compile script")
        }
        let descriptor = script.executeAndReturnError(&error)
        if let error = error {
            let number = error[NSAppleScript.errorNumber] as? Int
            // -1743 = not authorized to send Apple events; -600 = app not running.
            if number == -1743 { throw AppleNotesError.notAuthorized }
            if number == -600 { throw AppleNotesError.notesUnavailable }
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown AppleScript error"
            throw AppleNotesError.scriptFailed(message)
        }
        return descriptor.stringValue ?? ""
    }
}
