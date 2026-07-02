import Foundation
import RealmSwift

final class AppleNotesService {
    private let scripting: AppleNotesScripting

    init(scripting: AppleNotesScripting = AppleScriptNotesScripting()) {
        self.scripting = scripting
    }

    func availableFolders() -> Result<[String], AppleNotesError> {
        do {
            return .success(try scripting.listFolderNames())
        } catch let error as AppleNotesError {
            return .failure(error)
        } catch {
            return .failure(.scriptFailed(error.localizedDescription))
        }
    }

    func refresh(into realm: Realm) -> Result<AppleNotesSummary, AppleNotesError> {
        guard let folderName = SnippetSourceStore.appleNotesFolder else {
            return .failure(.folderNotFound)
        }
        do {
            let folder = try scripting.fetchFolder(named: folderName)
            let summary = AppleNotesImporter.rebuild(from: folder, into: realm)
            return .success(summary)
        } catch let error as AppleNotesError {
            return .failure(error)
        } catch {
            return .failure(.scriptFailed(error.localizedDescription))
        }
    }

    func refresh() -> Result<AppleNotesSummary, AppleNotesError> {
        guard let realm = AppleNotesSnippetCache.realm() else {
            return .failure(.scriptFailed("cache unavailable"))
        }
        return refresh(into: realm)
    }

    func revealSelectedFolder() {
        guard let folderName = SnippetSourceStore.appleNotesFolder else { return }
        try? scripting.revealFolder(named: folderName)
    }
}
