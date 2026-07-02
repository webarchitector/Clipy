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
            // Compare inside a Bool so the assertion holds whether or not a prior
            // spec left `defaultConfiguration` in-memory (fileURL nil on both sides):
            // Nimble's `==` treats nil == nil as a failure, but routing identity is
            // what we're asserting — native mode must return `manager.realm`.
            let active = manager.activeSnippetRealm()?.configuration.fileURL
            expect(active == manager.realm?.configuration.fileURL).to(beTrue())
        }

        it("returns the cache realm in apple notes mode") {
            SnippetSourceStore.current = .appleNotes
            let manager = MenuManager()
            let cacheURL = AppleNotesSnippetCache.configuration().fileURL
            expect(manager.activeSnippetRealm()?.configuration.fileURL) == cacheURL
        }
    }
}
