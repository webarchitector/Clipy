import Foundation
import RealmSwift

final class ScratchpadStore {
    private let realmProvider: () -> Realm?

    init(realmProvider: @escaping () -> Realm? = { Realm.safeInstance() }) {
        self.realmProvider = realmProvider
    }

    func allNotes() -> [CPYScratchNote] {
        guard let realm = realmProvider() else { return [] }
        return Array(realm.objects(CPYScratchNote.self)
            .sorted(byKeyPath: "updatedAt", ascending: false))
    }

    @discardableResult
    func create(content: String) -> String? {
        guard let realm = realmProvider() else { return nil }
        let note = CPYScratchNote()
        note.content = content
        let now = Date()
        note.createdAt = now
        note.updatedAt = now
        let identifier = note.identifier
        realm.transaction { realm.add(note) }
        return identifier
    }

    func update(id noteID: String, content: String) {
        guard let realm = realmProvider(),
              let note = realm.object(ofType: CPYScratchNote.self, forPrimaryKey: noteID) else { return }
        realm.transaction {
            note.content = content
            note.updatedAt = Date()
        }
    }

    func delete(id noteID: String) {
        guard let realm = realmProvider(),
              let note = realm.object(ofType: CPYScratchNote.self, forPrimaryKey: noteID) else { return }
        realm.transaction { realm.delete(note) }
    }

    func note(id noteID: String) -> CPYScratchNote? {
        guard let realm = realmProvider() else { return nil }
        return realm.object(ofType: CPYScratchNote.self, forPrimaryKey: noteID)
    }
}
