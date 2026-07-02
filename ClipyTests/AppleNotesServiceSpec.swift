import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

private struct StubScripting: AppleNotesScripting {
    let folders: [String]
    let folder: NotesFolderNode
    let error: AppleNotesError?

    func listFolderNames() throws -> [String] {
        if let error = error { throw error }
        return folders
    }
    func fetchFolder(named name: String) throws -> NotesFolderNode {
        if let error = error { throw error }
        return folder
    }
    func revealFolder(named name: String) throws {
        if let error = error { throw error }
    }
}

class AppleNotesServiceSpec: QuickSpec {
    override class func spec() {
        // Swift 6 strict concurrency: Quick `it` closures are @Sendable, so a
        // spec-scoped `var` captured across beforeEach + it would be a data-race.
        // Each test creates its own isolated Realm and UserDefaults instead.
        func makeRealm() -> Realm {
            var config = Realm.Configuration.defaultConfiguration
            config.inMemoryIdentifier = NSUUID().uuidString
            return try! Realm(configuration: config) // swiftlint:disable:this force_try
        }

        func prepareEnv() {
            let defaults = UserDefaults(suiteName: "AppleNotesServiceSpec-\(NSUUID().uuidString)")!
            AppEnvironment.replaceCurrent(environment: Environment(defaults: defaults))
            SnippetSourceStore.appleNotesFolder = "Snippets"
        }

        it("lists folders from scripting") {
            prepareEnv()
            let scripting = StubScripting(folders: ["A", "B"],
                                          folder: NotesFolderNode(title: "Snippets", snippets: [], subfolders: []),
                                          error: nil)
            let service = AppleNotesService(scripting: scripting)
            expect(service.availableFolders()) == .success(["A", "B"])
        }

        it("refreshes the cache from the selected folder") {
            prepareEnv()
            let realm = makeRealm()
            let folder = NotesFolderNode(title: "Snippets",
                                         snippets: [NotesSnippetNode(title: "x", content: "X")],
                                         subfolders: [])
            let service = AppleNotesService(scripting: StubScripting(folders: [], folder: folder, error: nil))
            let result = service.refresh(into: realm)
            expect(result) == .success(AppleNotesSummary(folderCount: 1, snippetCount: 1))
            expect(realm.objects(CPYSnippet.self).count) == 1
        }

        it("leaves the cache intact on error") {
            prepareEnv()
            let realm = makeRealm()
            let good = NotesFolderNode(title: "Snippets",
                                       snippets: [NotesSnippetNode(title: "x", content: "X")],
                                       subfolders: [])
            _ = AppleNotesService(scripting: StubScripting(folders: [], folder: good, error: nil)).refresh(into: realm)
            let failing = AppleNotesService(scripting: StubScripting(folders: [], folder: good, error: .notAuthorized))
            let result = failing.refresh(into: realm)
            expect(result) == .failure(.notAuthorized)
            expect(realm.objects(CPYSnippet.self).count) == 1
        }

        it("fails when no folder is selected") {
            prepareEnv()
            let realm = makeRealm()
            SnippetSourceStore.appleNotesFolder = nil
            let service = AppleNotesService(
                scripting: StubScripting(folders: [],
                                         folder: NotesFolderNode(title: "", snippets: [], subfolders: []),
                                         error: nil))
            expect(service.refresh(into: realm)) == .failure(.folderNotFound)
        }
    }
}
