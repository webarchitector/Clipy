import Foundation

struct NotesSnippetNode: Sendable, Equatable {
    let title: String
    let content: String
}

struct NotesFolderNode: Sendable, Equatable {
    let title: String
    var snippets: [NotesSnippetNode]
    var subfolders: [NotesFolderNode]
}

struct AppleNotesSummary: Sendable, Equatable {
    let folderCount: Int
    let snippetCount: Int
}

enum AppleNotesError: Error, Equatable {
    case notAuthorized
    case notesUnavailable
    case folderNotFound
    case scriptFailed(String)
}
