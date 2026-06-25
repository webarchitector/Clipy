import Foundation
import Quick
import Nimble
import RealmSwift
@testable import Clipy

class ScratchpadStoreSpec: QuickSpec {
    override class func spec() {
        describe("ScratchpadStore") {
            func makeRealm() -> Realm {
                let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString,
                                                 objectTypes: [CPYScratchNote.self])
                return try! Realm(configuration: config)
            }

            it("creates and lists notes, newest first") {
                let realm = makeRealm()
                let store = ScratchpadStore(realmProvider: { realm })
                let first = store.create(content: "first")
                let second = store.create(content: "second")
                expect(first) != nil
                expect(second) != nil
                let notes = store.allNotes()
                expect(notes.count) == 2
                expect(notes.first?.identifier) == second
            }

            it("updates content and bumps order to the top") {
                let realm = makeRealm()
                let store = ScratchpadStore(realmProvider: { realm })
                let alpha = store.create(content: "A")!
                let beta = store.create(content: "B")!
                store.update(id: alpha, content: "A edited")
                let notes = store.allNotes()
                expect(notes.first?.identifier) == alpha
                expect(store.note(id: alpha)?.content) == "A edited"
                expect(beta) != nil
            }

            it("deletes notes") {
                let realm = makeRealm()
                let store = ScratchpadStore(realmProvider: { realm })
                let identifier = store.create(content: "x")!
                store.delete(id: identifier)
                expect(store.allNotes().count) == 0
                expect(store.note(id: identifier)) == nil
            }

            it("is a no-op when Realm is unavailable") {
                let store = ScratchpadStore(realmProvider: { nil })
                expect(store.create(content: "x")) == nil
                expect(store.allNotes()).to(beEmpty())
                store.update(id: "missing", content: "y")
                store.delete(id: "missing")
            }
        }
    }
}
