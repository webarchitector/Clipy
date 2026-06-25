import Foundation
import RealmSwift

final class CPYScratchNote: Object {
    @objc dynamic var identifier = UUID().uuidString
    @objc dynamic var content = ""
    @objc dynamic var createdAt = Date()
    @objc dynamic var updatedAt = Date()

    override static func primaryKey() -> String? {
        return "identifier"
    }
}
