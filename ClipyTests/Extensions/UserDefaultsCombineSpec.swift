import Quick
import Nimble
import Foundation
import Combine
@testable import Clipy

class UserDefaultsCombineSpec: QuickSpec {
    override class func spec() {
        describe("UserDefaults+Combine") {

            // Use an isolated suite so test changes don't leak into the real
            // host defaults (and so other tests can't poison this one).
            var defaults: UserDefaults!
            let suiteName = "com.clipy-app.Clipy.UserDefaultsCombineSpec"

            beforeEach {
                UserDefaults().removePersistentDomain(forName: suiteName)
                defaults = UserDefaults(suiteName: suiteName)
            }

            afterEach {
                defaults.removePersistentDomain(forName: suiteName)
                defaults = nil
            }

            describe("boolPublisher") {
                it("emits the current value on subscribe") {
                    defaults.set(true, forKey: "flag")
                    var received: [Bool] = []
                    let cancellable = defaults.boolPublisher(forKey: "flag")
                        .sink { received.append($0) }
                    expect(received) == [true]
                    cancellable.cancel()
                }

                it("emits false for unset key") {
                    var received: [Bool] = []
                    let cancellable = defaults.boolPublisher(forKey: "missing")
                        .sink { received.append($0) }
                    expect(received) == [false]
                    cancellable.cancel()
                }

                it("re-emits when the value changes") {
                    defaults.set(false, forKey: "flag")
                    var received: [Bool] = []
                    let cancellable = defaults.boolPublisher(forKey: "flag")
                        .sink { received.append($0) }
                    defaults.set(true, forKey: "flag")
                    expect(received).toEventually(equal([false, true]))
                    cancellable.cancel()
                }

                it("removeDuplicates suppresses unchanged re-emits") {
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
                    defaults.set(42, forKey: "n")
                    var received: [Int] = []
                    let cancellable = defaults.integerPublisher(forKey: "n")
                        .sink { received.append($0) }
                    expect(received) == [42]
                    cancellable.cancel()
                }

                it("emits 0 for unset key") {
                    var received: [Int] = []
                    let cancellable = defaults.integerPublisher(forKey: "missing")
                        .sink { received.append($0) }
                    expect(received) == [0]
                    cancellable.cancel()
                }

                it("re-emits on change") {
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
