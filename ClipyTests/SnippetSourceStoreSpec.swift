import Quick
import Nimble
import Foundation
@testable import Clipy

class SnippetSourceStoreSpec: QuickSpec {
    override class func spec() {
        // Swift 6 strict concurrency: Quick `it` closures are @Sendable,
        // so spec-scoped `var`s cannot be shared across beforeEach + it.
        // Each test builds its own isolated UserDefaults instead.
        func makeDefaults() -> UserDefaults {
            let suite = "SnippetSourceStoreSpec-\(NSUUID().uuidString)"
            let defs = UserDefaults(suiteName: suite)!
            AppEnvironment.replaceCurrent(environment: Environment(defaults: defs))
            return defs
        }

        it("defaults to native when unset") {
            _ = makeDefaults()
            expect(SnippetSourceStore.current) == SnippetSource.native
        }

        it("round-trips the selected source") {
            let defaults = makeDefaults()
            SnippetSourceStore.current = .appleNotes
            expect(SnippetSourceStore.current) == SnippetSource.appleNotes
            expect(defaults.integer(forKey: Constants.UserDefaults.snippetSource)) == 1
        }

        it("round-trips the selected folder name") {
            _ = makeDefaults()
            SnippetSourceStore.appleNotesFolder = "Snippets"
            expect(SnippetSourceStore.appleNotesFolder) == "Snippets"
        }
    }
}
