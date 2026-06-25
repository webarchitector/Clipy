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
        let id = note.identifier
        realm.transaction { realm.add(note) }
        return id
    }

    func update(id: String, content: String) {
        guard let realm = realmProvider(),
              let note = realm.object(ofType: CPYScratchNote.self, forPrimaryKey: id) else { return }
        realm.transaction {
            note.content = content
            note.updatedAt = Date()
        }
    }

    func delete(id: String) {
        guard let realm = realmProvider(),
              let note = realm.object(ofType: CPYScratchNote.self, forPrimaryKey: id) else { return }
        realm.transaction { realm.delete(note) }
    }

    func note(id: String) -> CPYScratchNote? {
        guard let realm = realmProvider() else { return nil }
        return realm.object(ofType: CPYScratchNote.self, forPrimaryKey: id)
    }
}
