// swiftlint:disable identifier_name

import Quick
import Nimble
import Cocoa
import RealmSwift
@testable import Clipy

class PasteServiceCacheSpec: QuickSpec {
    override class func spec() {
        describe("PasteService.cachedClipData(for:)") {

            // CPYClip's primary key is dataHash; cachedClipData uses dataPath
            // (the on-disk archive) as the cache key. We need a realm to hold
            // the clip and a temp file to back it. Each test owns its own
            // (Swift 6 strict concurrency rejects spec-scoped `var`s through
            // Quick's @Sendable `it` closures).

            func makeFixture() -> (PasteService, URL) {
                Realm.Configuration.defaultConfiguration = Realm.Configuration(
                    inMemoryIdentifier: UUID().uuidString,
                    objectTypes: [CPYClip.self, CPYFolder.self, CPYSnippet.self]
                )
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PasteServiceCacheSpec-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                return (PasteService(), tmpDir)
            }

            // Helper: create a clip whose dataPath holds an archived CPYClipData
            // we can decode back. dataPath uniqueness keeps cache keys distinct
            // between tests.
            func makeClipOnDisk(stringValue: String, in tmpDir: URL) -> CPYClip {
                let payload = CPYClipData(image: NSImage())
                payload.types = [.string]
                payload.stringValue = stringValue

                let path = tmpDir.appendingPathComponent("\(UUID().uuidString).data").path
                let archived = LegacyKeyedArchive.archiveRootObject(payload, toFile: path)
                expect(archived) == true

                let realm = try! Realm()
                let clip = CPYClip()
                clip.dataHash = UUID().uuidString
                clip.title = stringValue
                clip.dataPath = path
                clip.primaryType = NSPasteboard.PasteboardType.string.rawValue
                try! realm.write { realm.add(clip) }
                return clip
            }

            it("returns nil when the underlying file is missing") {
                let (service, tmpDir) = makeFixture()
                defer { try? FileManager.default.removeItem(at: tmpDir) }
                let realm = try! Realm()
                let clip = CPYClip()
                clip.dataHash = "missing"
                clip.dataPath = "/tmp/definitely-not-here-\(UUID().uuidString).data"
                try! realm.write { realm.add(clip) }
                expect(service.cachedClipData(for: clip)) == nil
            }

            it("decodes the archive on first lookup") {
                let (service, tmpDir) = makeFixture()
                defer { try? FileManager.default.removeItem(at: tmpDir) }
                let clip = makeClipOnDisk(stringValue: "hello", in: tmpDir)
                let result = service.cachedClipData(for: clip)
                expect(result) != nil
                expect(result?.stringValue) == "hello"
            }

            it("caches the decoded value so a second lookup doesn't re-read disk") {
                let (service, tmpDir) = makeFixture()
                defer { try? FileManager.default.removeItem(at: tmpDir) }
                let clip = makeClipOnDisk(stringValue: "cacheable", in: tmpDir)
                let first = service.cachedClipData(for: clip)
                expect(first) != nil

                // Delete the underlying file. If the cache works, the second
                // lookup still returns the same data.
                try? FileManager.default.removeItem(atPath: clip.dataPath)
                let second = service.cachedClipData(for: clip)
                expect(second) != nil
                expect(second?.stringValue) == "cacheable"
            }

            it("treats different clips with different dataPaths as separate cache entries") {
                let (service, tmpDir) = makeFixture()
                defer { try? FileManager.default.removeItem(at: tmpDir) }
                let a = makeClipOnDisk(stringValue: "alpha", in: tmpDir)
                let b = makeClipOnDisk(stringValue: "beta", in: tmpDir)
                let resultA = service.cachedClipData(for: a)
                let resultB = service.cachedClipData(for: b)
                expect(resultA?.stringValue) == "alpha"
                expect(resultB?.stringValue) == "beta"
            }
        }
    }
}
