import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class AppleNotesImporterSpec: QuickSpec {
    override class func spec() {
        // Swift 6 strict concurrency: Quick `it` closures are @Sendable, so a
        // spec-scoped `var realm` captured across beforeEach + it would be a
        // data-race. Each test creates its own isolated in-memory Realm instead.
        func makeRealm() -> Realm {
            var config = Realm.Configuration.defaultConfiguration
            config.inMemoryIdentifier = NSUUID().uuidString
            return try! Realm(configuration: config) // swiftlint:disable:this force_try
        }

        describe("flatten") {
            it("collapses folders deeper than maxDepth, lifting their snippets") {
                // depth: root(1) > folderA(2) > folderB(3) — with maxDepth 2, folderB is
                // removed and its snippet is appended to folderA.
                let folderB = NotesFolderNode(title: "b",
                                              snippets: [NotesSnippetNode(title: "deep", content: "D")],
                                              subfolders: [])
                let folderA = NotesFolderNode(title: "a", snippets: [], subfolders: [folderB])
                let root = NotesFolderNode(title: "root", snippets: [], subfolders: [folderA])

                let flat = AppleNotesImporter.flatten(root, maxDepth: 2)
                expect(flat.subfolders.count) == 1
                let flatA = flat.subfolders[0]
                expect(flatA.title) == "a"
                expect(flatA.subfolders).to(beEmpty())
                expect(flatA.snippets.map { $0.title }) == ["deep"]
            }
        }

        describe("rebuild") {
            it("writes the folder as a single enabled root with mapped children") {
                let realm = makeRealm()
                let sub = NotesFolderNode(title: "Sub",
                                          snippets: [NotesSnippetNode(title: "y", content: "Y")],
                                          subfolders: [])
                let root = NotesFolderNode(title: "Snippets",
                                           snippets: [NotesSnippetNode(title: "x", content: "X")],
                                           subfolders: [sub])

                let summary = AppleNotesImporter.rebuild(from: root, into: realm)
                expect(summary.folderCount) == 2
                expect(summary.snippetCount) == 2

                let roots = realm.objects(CPYFolder.self).filter("parentIdentifier == ''")
                expect(roots.count) == 1
                let rootFolder = roots.first!
                expect(rootFolder.title) == "Snippets"
                expect(rootFolder.enable) == true

                let kids = CPYFolder.children(parentIdentifier: rootFolder.identifier, in: realm)
                // Folders sort before snippets only by index; both start at 0 here,
                // so assert by membership.
                let kidFolders = kids.compactMap { $0 as? CPYFolder }
                let kidSnippets = kids.compactMap { $0 as? CPYSnippet }
                expect(kidFolders.map { $0.title }) == ["Sub"]
                expect(kidSnippets.map { $0.title }) == ["x"]
                expect(kidSnippets.first?.content) == "X"
            }

            it("wipes the previous cache on each rebuild") {
                let realm = makeRealm()
                let first = NotesFolderNode(title: "Old", snippets: [], subfolders: [])
                _ = AppleNotesImporter.rebuild(from: first, into: realm)
                let second = NotesFolderNode(title: "New",
                                             snippets: [NotesSnippetNode(title: "n", content: "N")],
                                             subfolders: [])
                let summary = AppleNotesImporter.rebuild(from: second, into: realm)

                expect(summary.folderCount) == 1
                expect(realm.objects(CPYFolder.self).count) == 1
                expect(realm.objects(CPYFolder.self).first?.title) == "New"
                expect(realm.objects(CPYSnippet.self).count) == 1
            }
        }
    }
}
