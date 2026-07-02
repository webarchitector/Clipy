import Foundation
import RealmSwift

enum AppleNotesImporter {
    static let maxFolderDepth = 5

    /// Collapse folders deeper than `maxDepth`. `depth` is 1-based for the passed
    /// folder. When a subfolder would exceed the limit, it is dropped and every
    /// snippet in its (recursively collapsed) subtree is lifted into `folder`.
    static func flatten(_ folder: NotesFolderNode, maxDepth: Int = maxFolderDepth) -> NotesFolderNode {
        return flatten(folder, depth: 1, maxDepth: maxDepth)
    }

    private static func flatten(_ folder: NotesFolderNode, depth: Int, maxDepth: Int) -> NotesFolderNode {
        var snippets = folder.snippets
        var subfolders: [NotesFolderNode] = []
        for sub in folder.subfolders {
            if depth + 1 > maxDepth {
                snippets.append(contentsOf: collectSnippets(sub))
            } else {
                subfolders.append(flatten(sub, depth: depth + 1, maxDepth: maxDepth))
            }
        }
        return NotesFolderNode(title: folder.title, snippets: snippets, subfolders: subfolders)
    }

    private static func collectSnippets(_ folder: NotesFolderNode) -> [NotesSnippetNode] {
        var result = folder.snippets
        for sub in folder.subfolders {
            result.append(contentsOf: collectSnippets(sub))
        }
        return result
    }

    @discardableResult
    static func rebuild(from folder: NotesFolderNode, into realm: Realm) -> AppleNotesSummary {
        let capped = flatten(folder)
        var folderCount = 0
        var snippetCount = 0
        realm.transaction {
            realm.delete(realm.objects(CPYSnippet.self))
            realm.delete(realm.objects(CPYFolder.self))
            let counts = write(capped, parentIdentifier: "", index: 0, in: realm)
            folderCount = counts.folders
            snippetCount = counts.snippets
        }
        return AppleNotesSummary(folderCount: folderCount, snippetCount: snippetCount)
    }

    private static func write(_ node: NotesFolderNode, parentIdentifier: String, index: Int, in realm: Realm) -> (folders: Int, snippets: Int) {
        let folder = CPYFolder()
        folder.title = node.title
        folder.enable = true
        folder.index = index
        folder.parentIdentifier = parentIdentifier
        realm.add(folder)

        var folders = 1
        var snippets = 0
        var childIndex = 0

        for sub in node.subfolders {
            let counts = write(sub, parentIdentifier: folder.identifier, index: childIndex, in: realm)
            folders += counts.folders
            snippets += counts.snippets
            childIndex += 1
        }
        for snippetNode in node.snippets {
            let snippet = CPYSnippet()
            snippet.title = snippetNode.title
            snippet.content = snippetNode.content
            snippet.enable = true
            snippet.index = childIndex
            snippet.parentIdentifier = folder.identifier
            realm.add(snippet)
            snippets += 1
            childIndex += 1
        }
        return (folders, snippets)
    }
}
