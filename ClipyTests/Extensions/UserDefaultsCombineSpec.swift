import Quick
import Nimble
import Foundation
import Combine
@testable import Clipy

class UserDefaultsCombineSpec: QuickSpec {
    override class func spec() {
        describe("UserDefaults+Combine") {

            // Each test owns its own isolated suite (Swift 6 strict
            // concurrency rejects sharing UserDefaults across @Sendable
            // `it` closures via spec-scoped vars). The suite name is
            // unique per test so writes can't leak between them either.

            func makeIsolatedDefaults() -> UserDefaults {
                let suiteName = "com.clipy-app.Clipy.UserDefaultsCombineSpec.\(UUID().uuidString)"
                UserDefaults().removePersistentDomain(forName: suiteName)
                return UserDefaults(suiteName: suiteName)!
            }

            describe("boolPublisher") {
                it("emits the current value on subscribe") {
                    let defaults = makeIsolatedDefaults()
                    defaults.set(true, forKey: "flag")
                    var received: [Bool] = []
                    let cancellable = defaults.boolPublisher(forKey: "flag")
                        .sink { received.append($0) }
                    expect(received) == [true]
                    cancellable.cancel()
                }

                it("emits false for unset key") {
                    let defaults = makeIsolatedDefaults()
                    var received: [Bool] = []
                    let cancellable = defaults.boolPublisher(forKey: "missing")
                        .sink { received.append($0) }
                    expect(received) == [false]
                    cancellable.cancel()
                }

                it("re-emits when the value changes") {
                    let defaults = makeIsolatedDefaults()
                    defaults.set(false, forKey: "flag")
                    var received: [Bool] = []
                    let cancellable = defaults.boolPublisher(forKey: "flag")
                        .sink { received.append($0) }
                    defaults.set(true, forKey: "flag")
                    expect(received).toEventually(equal([false, true]))
                    cancellable.cancel()
                }

                it("removeDuplicates suppresses unchanged re-emits") {
                    let defaults = makeIsolatedDefaults()
                    defaults.set(true, forKey: "flag")
                    var received: [Bool] = []
                    let cancellable = defaults.boolPublisher(forKey: "flag")
                        .sink { received.append($0) }
                    // Trigger didChangeNotification with same value
                    defaults.set(true, forKey: "flag")
                    defaults.set("unrelated", forKey: "other")
                    expect(received).toEventually(equal([true]))
                    cancellable.cancel()
                }
            }

            describe("integerPublisher") {
                it("emits the current value on subscribe") {
                    let defaults = makeIsolatedDefaults()
                    defaults.set(42, forKey: "n")
                    var received: [Int] = []
                    let cancellable = defaults.integerPublisher(forKey: "n")
                        .sink { received.append($0) }
                    expect(received) == [42]
                    cancellable.cancel()
                }

                it("emits 0 for unset key") {
                    let defaults = makeIsolatedDefaults()
                    var received: [Int] = []
                    let cancellable = defaults.integerPublisher(forKey: "missing")
                        .sink { received.append($0) }
                    expect(received) == [0]
                    cancellable.cancel()
                }

                it("re-emits on change") {
                    let defaults = makeIsolatedDefaults()
                    defaults.set(1, forKey: "n")
                    var received: [Int] = []
                    let cancellable = defaults.integerPublisher(forKey: "n")
                        .sink { received.append($0) }
                    defaults.set(2, forKey: "n")
                    expect(received).toEventually(equal([1, 2]))
                    cancellable.cancel()
                }
            }

            describe("dictionaryPublisher") {
                it("emits the current dictionary on subscribe") {
                    let defaults = makeIsolatedDefaults()
                    let initial: [String: NSNumber] = ["a": 1, "b": 2]
                    defaults.set(initial, forKey: "dict")
                    var received: [[String: NSNumber]] = []
                    let cancellable = defaults.dictionaryPublisher(forKey: "dict")
                        .sink { received.append($0) }
                    expect(received.count) == 1
                    expect(received[0]["a"]) == 1
                    expect(received[0]["b"]) == 2
                    cancellable.cancel()
                }

                it("emits an empty dictionary for unset key") {
                    let defaults = makeIsolatedDefaults()
                    var received: [[String: NSNumber]] = []
                    let cancellable = defaults.dictionaryPublisher(forKey: "missing")
                        .sink { received.append($0) }
                    expect(received.count) == 1
                    expect(received[0]).to(beEmpty())
                    cancellable.cancel()
                }
            }
        }
    }
}
