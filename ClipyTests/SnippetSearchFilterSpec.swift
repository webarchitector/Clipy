import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class SnippetSearchFilterSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        afterEach {
            let realm = try! Realm()
            try? realm.write { realm.deleteAll() }
        }

        describe("visibleIdentifiers") {

            it("returns nil for an empty query") {
                let realm = try! Realm()
                expect(SnippetSearchFilter.visibleIdentifiers(query: "", in: realm)) == nil
            }

            it("returns nil for a whitespace-only query") {
                let realm = try! Realm()
                expect(SnippetSearchFilter.visibleIdentifiers(query: "   \t\n", in: realm)) == nil
            }

            it("returns an empty set when there are no matches") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.title = "F"; folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "alpha"; snippet.content = "beta"
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "zzz", in: realm)
                expect(result) != nil
                expect(result?.isEmpty) == true
            }

            it("matches snippet title (case-insensitive)") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "Hello World"; snippet.content = ""
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "hello", in: realm)
                expect(result?.contains(snippet.identifier)) == true
                expect(result?.contains(folder.identifier)) == true
            }

            it("matches snippet content") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "untitled"; snippet.content = "secret payload"
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "payload", in: realm)
                expect(result?.contains(snippet.identifier)) == true
                expect(result?.contains(folder.identifier)) == true
            }

            it("is diacritic-insensitive") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "José"; snippet.content = ""
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "jose", in: realm)
                expect(result?.contains(snippet.identifier)) == true
            }

            it("does NOT match folder titles") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.title = "Greetings"; folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.title = "x"; snippet.content = "y"
                snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }
                let result = SnippetSearchFilter.visibleIdentifiers(query: "Greetings", in: realm)
                expect(result?.isEmpty) == true
            }

            it("includes the full ancestor chain for a deeply nested match") {
                let realm = try! Realm()
                var prevID = ""
                var folderIDs: [String] = []
                for level in 0..<5 {
                    let folder = CPYFolder(); folder.title = "L\(level + 1)"; folder.index = 0
                    folder.parentIdentifier = prevID
                    try! realm.write { realm.add(folder) }
                    folderIDs.append(folder.identifier)
                    prevID = folder.identifier
                }
                let snippet = CPYSnippet(); snippet.title = "needle"; snippet.content = ""
                snippet.parentIdentifier = prevID; snippet.index = 0
                try! realm.write { realm.add(snippet) }

                let result = SnippetSearchFilter.visibleIdentifiers(query: "needle", in: realm)
                expect(result?.contains(snippet.identifier)) == true
                for fid in folderIDs {
                    expect(result?.contains(fid)) == true
                }
            }
        }
    }
}
