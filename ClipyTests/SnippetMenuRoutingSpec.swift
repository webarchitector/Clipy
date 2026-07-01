import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class SnippetMenuRoutingSpec: QuickSpec {
    override class func spec() {
        beforeEach {
            let defaults = UserDefaults(suiteName: "SnippetMenuRoutingSpec-\(NSUUID().uuidString)")!
            AppEnvironment.replaceCurrent(environment: Environment(defaults: defaults))
        }

        it("returns the native realm in native mode") {
            SnippetSourceStore.current = .native
            let manager = MenuManager()
            expect(manager.activeSnippetRealm()?.configuration.fileURL)
                == manager.realm?.configuration.fileURL
        }

        it("returns the cache realm in apple notes mode") {
            SnippetSourceStore.current = .appleNotes
            let manager = MenuManager()
            let cacheURL = AppleNotesSnippetCache.configuration().fileURL
            expect(manager.activeSnippetRealm()?.configuration.fileURL) == cacheURL
        }
    }
}
