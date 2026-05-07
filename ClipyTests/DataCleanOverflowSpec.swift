import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class DataCleanOverflowSpec: QuickSpec {
    override class func spec() {
        describe("DataCleanService.overflowingClips(with:)") {

            // Each test owns its own in-memory Realm + service. Swift 6
            // strict concurrency rejects sharing them via spec-scoped `var`s
            // through Quick's @Sendable `it` closures.

            // Insert N clips with strictly increasing updateTime so we can
            // tell the "old" ones from the "new" ones by predicate.
            func makeRealm() -> Realm {
                let config = Realm.Configuration(
                    inMemoryIdentifier: UUID().uuidString,
                    objectTypes: [CPYClip.self, CPYFolder.self, CPYSnippet.self]
                )
                return try! Realm(configuration: config)
            }

            func seed(_ realm: Realm, count: Int) {
                try! realm.write {
                    for i in 0..<count {
                        let clip = CPYClip()
                        clip.dataHash = "h\(i)"
                        clip.title = "title \(i)"
                        clip.updateTime = i
                        clip.dataPath = "/tmp/clip-\(i).data"
                        realm.add(clip)
                    }
                }
            }

            func setMaxHistory(_ value: Int) {
                AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.maxHistorySize)
            }

            func clearMaxHistoryDefault() {
                AppEnvironment.current.defaults.removeObject(forKey: Constants.UserDefaults.maxHistorySize)
            }

            describe("when maxHistorySize <= 0") {

                // Regression for: a single zero in Preferences silently wipes
                // the entire clipboard history. The fix treats <= 0 as
                // "no limit" — overflowingClips must return empty.
                it("returns empty when maxHistorySize == 0 (no-limit)") {
                    let realm = makeRealm()
                    let service = DataCleanService()
                    seed(realm, count: 5)
                    setMaxHistory(0)
                    defer { clearMaxHistoryDefault() }
                    expect(service.overflowingClips(with: realm).count) == 0
                }

                it("returns empty for negative values too") {
                    let realm = makeRealm()
                    let service = DataCleanService()
                    seed(realm, count: 5)
                    setMaxHistory(-3)
                    defer { clearMaxHistoryDefault() }
                    expect(service.overflowingClips(with: realm).count) == 0
                }
            }

            describe("when clip count fits the limit") {
                it("returns empty when count == max") {
                    let realm = makeRealm()
                    let service = DataCleanService()
                    seed(realm, count: 10)
                    setMaxHistory(10)
                    defer { clearMaxHistoryDefault() }
                    expect(service.overflowingClips(with: realm).count) == 0
                }

                it("returns empty when count < max") {
                    let realm = makeRealm()
                    let service = DataCleanService()
                    seed(realm, count: 3)
                    setMaxHistory(10)
                    defer { clearMaxHistoryDefault() }
                    expect(service.overflowingClips(with: realm).count) == 0
                }
            }

            describe("when clip count exceeds the limit") {
                it("flags the clips older than the Nth-newest for deletion") {
                    let realm = makeRealm()
                    let service = DataCleanService()
                    seed(realm, count: 10)
                    setMaxHistory(3)
                    defer { clearMaxHistoryDefault() }
                    // Newest 3 are updateTime = 9, 8, 7. The boundary clip
                    // (the 3rd-newest) has updateTime = 7. Everything with
                    // updateTime < 7 should be marked for deletion → 7 clips.
                    expect(service.overflowingClips(with: realm).count) == 7
                }

                it("keeps exactly maxHistorySize clips after deletion") {
                    let realm = makeRealm()
                    let service = DataCleanService()
                    seed(realm, count: 50)
                    setMaxHistory(20)
                    defer { clearMaxHistoryDefault() }
                    let toDelete = service.overflowingClips(with: realm)
                    try! realm.write { realm.delete(toDelete) }
                    expect(realm.objects(CPYClip.self).count) == 20
                }
            }
        }
    }
}
