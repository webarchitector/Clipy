import Foundation

protocol AppleNotesScripting: Sendable {
    func listFolderNames() throws -> [String]
    func fetchFolder(named name: String) throws -> NotesFolderNode
    func revealFolder(named name: String) throws
}

enum NotesOutputParser {
    private static let recordSeparator = "\u{1D}"
    private static let fieldSeparator = "\u{1E}"

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
}

struct AppleScriptNotesScripting: AppleNotesScripting {
    private static let recordSeparator = "\u{1D}"
    private static let fieldSeparator = "\u{1E}"

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
        let source = """
        tell application "Notes"
            set out to ""
            set theFolder to first folder whose name is "\(escaped)"
            repeat with n in notes of theFolder
                set out to out & (name of n) & "\(Self.fieldSeparator)" & (plaintext of n) & "\(Self.recordSeparator)"
            end repeat
            return out
        end tell
        """
        return NotesOutputParser.parseNotes(try run(source), folderName: name)
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
