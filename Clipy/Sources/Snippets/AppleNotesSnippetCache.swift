import Foundation
import os
import RealmSwift

private let cacheLog = Logger(subsystem: "com.clipy-app.Clipy", category: "apple-notes-cache")

enum AppleNotesSnippetCache {
    static func fileURL() -> URL {
        let folder = CPYUtilities.applicationSupportFolder()
        _ = CPYUtilities.prepareSaveToPath(folder)
        return URL(fileURLWithPath: folder).appendingPathComponent("apple-notes-snippets.realm")
    }

    static func configuration() -> Realm.Configuration {
        // Separate file + explicit object types so this cache never shares
        // state or migrations with the native default Realm.
        return Realm.Configuration(fileURL: fileURL(),
                                   schemaVersion: 1,
                                   objectTypes: [CPYFolder.self, CPYSnippet.self])
    }

    static func realm() -> Realm? {
        do {
            return try Realm(configuration: configuration())
        } catch {
            cacheLog.error("Apple Notes cache Realm init failed: \(error.localizedDescription, privacy: .public)")
            assertionFailure("Apple Notes cache Realm init failed: \(error)")
            return nil
        }
    }
}
