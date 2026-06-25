// swiftlint:disable identifier_name
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
                let id1 = store.create(content: "first")
                let id2 = store.create(content: "second")
                expect(id1).toNot(beNil())
                expect(id2).toNot(beNil())
                let notes = store.allNotes()
                expect(notes.count).to(equal(2))
                expect(notes.first?.identifier).to(equal(id2))
            }

            it("updates content and bumps order to the top") {
                let realm = makeRealm()
                let store = ScratchpadStore(realmProvider: { realm })
                let idA = store.create(content: "A")!
                let idB = store.create(content: "B")!
                store.update(id: idA, content: "A edited")
                let notes = store.allNotes()
                expect(notes.first?.identifier).to(equal(idA))
                expect(store.note(id: idA)?.content).to(equal("A edited"))
                expect(idB).toNot(beNil())
            }

            it("deletes notes") {
                let realm = makeRealm()
                let store = ScratchpadStore(realmProvider: { realm })
                let id = store.create(content: "x")!
                store.delete(id: id)
                expect(store.allNotes().count).to(equal(0))
                expect(store.note(id: id)).to(beNil())
            }

            it("is a no-op when Realm is unavailable") {
                let store = ScratchpadStore(realmProvider: { nil })
                expect(store.create(content: "x")).to(beNil())
                expect(store.allNotes()).to(beEmpty())
                store.update(id: "missing", content: "y")
                store.delete(id: "missing")
            }
        }
    }
}
