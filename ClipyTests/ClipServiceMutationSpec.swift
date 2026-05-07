import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class ClipServiceMutationSpec: QuickSpec {
    override class func spec() {
        describe("ClipService mutations against an in-memory Realm") {

            // ClipService grabs the current Realm via `Realm.safeInstance()`,
            // which honors the default configuration. Pointing that at an
            // in-memory store gives us isolated test data per spec.
            beforeEach {
                Realm.Configuration.defaultConfiguration = Realm.Configuration(
                    inMemoryIdentifier: UUID().uuidString,
                    objectTypes: [CPYClip.self, CPYFolder.self, CPYSnippet.self]
                )
            }

            // Helper: insert N clips with unique primary keys / dataPaths.
            func seed(count: Int) -> [String] {
                let realm = try! Realm()
                var hashes: [String] = []
                try! realm.write {
                    for i in 0..<count {
                        let clip = CPYClip()
                        clip.dataHash = "h\(i)"
                        clip.title = "title \(i)"
                        clip.updateTime = i
                        clip.dataPath = "/tmp/clip-\(UUID().uuidString).data"
                        realm.add(clip)
                        hashes.append(clip.dataHash)
                    }
                }
                return hashes
            }

            describe("delete(with:)") {
                it("removes the supplied clip from Realm") {
                    let hashes = seed(count: 3)
                    let realm = try! Realm()
                    let target = realm.object(ofType: CPYClip.self, forPrimaryKey: hashes[1])!

                    ClipService().delete(with: target)

                    let remaining = realm.objects(CPYClip.self).map { $0.dataHash }
                    expect(Set(remaining)) == Set([hashes[0], hashes[2]])
                }

                it("is a no-op when the clip is the only one and matches no other state") {
                    _ = seed(count: 1)
                    let realm = try! Realm()
                    let only = realm.objects(CPYClip.self).first!

                    ClipService().delete(with: only)

                    expect(realm.objects(CPYClip.self).count) == 0
                }
            }

            describe("clearAll()") {
                it("removes every clip in the realm") {
                    _ = seed(count: 7)
                    let realm = try! Realm()
                    expect(realm.objects(CPYClip.self).count) == 7

                    ClipService().clearAll()

                    expect(realm.objects(CPYClip.self).count) == 0
                }

                it("leaves snippets and folders alone (only clips are wiped)") {
                    _ = seed(count: 3)
                    let realm = try! Realm()
                    try! realm.write {
                        let folder = CPYFolder()
                        folder.identifier = UUID().uuidString
                        folder.title = "F"
                        realm.add(folder)
                    }

                    ClipService().clearAll()

                    expect(realm.objects(CPYClip.self).count) == 0
                    expect(realm.objects(CPYFolder.self).count) == 1
                }

                it("is safe on an already-empty realm") {
                    expect { ClipService().clearAll() }.toNot(throwAssertion())
                    let realm = try! Realm()
                    expect(realm.objects(CPYClip.self).count) == 0
                }
            }
        }
    }
}
