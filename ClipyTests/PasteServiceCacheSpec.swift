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
            // the clip and a temp file to back it.
            var tmpDir: URL!
            var service: PasteService!

            beforeEach {
                Realm.Configuration.defaultConfiguration = Realm.Configuration(
                    inMemoryIdentifier: UUID().uuidString,
                    objectTypes: [CPYClip.self, CPYFolder.self, CPYSnippet.self]
                )
                tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PasteServiceCacheSpec-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                service = PasteService()
            }

            afterEach {
                try? FileManager.default.removeItem(at: tmpDir)
                service = nil
            }

            // Helper: create a clip whose dataPath holds an archived CPYClipData
            // we can decode back. dataPath uniqueness keeps cache keys distinct
            // between tests.
            func makeClipOnDisk(stringValue: String) -> CPYClip {
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
                let realm = try! Realm()
                let clip = CPYClip()
                clip.dataHash = "missing"
                clip.dataPath = "/tmp/definitely-not-here-\(UUID().uuidString).data"
                try! realm.write { realm.add(clip) }
                expect(service.cachedClipData(for: clip)).to(beNil())
            }

            it("decodes the archive on first lookup") {
                let clip = makeClipOnDisk(stringValue: "hello")
                let result = service.cachedClipData(for: clip)
                expect(result).toNot(beNil())
                expect(result?.stringValue) == "hello"
            }

            it("caches the decoded value so a second lookup doesn't re-read disk") {
                let clip = makeClipOnDisk(stringValue: "cacheable")
                let first = service.cachedClipData(for: clip)
                expect(first).toNot(beNil())

                // Delete the underlying file. If the cache works, the second
                // lookup still returns the same data.
                try? FileManager.default.removeItem(atPath: clip.dataPath)
                let second = service.cachedClipData(for: clip)
                expect(second).toNot(beNil())
                expect(second?.stringValue) == "cacheable"
            }

            it("treats different clips with different dataPaths as separate cache entries") {
                let a = makeClipOnDisk(stringValue: "alpha")
                let b = makeClipOnDisk(stringValue: "beta")
                let resultA = service.cachedClipData(for: a)
                let resultB = service.cachedClipData(for: b)
                expect(resultA?.stringValue) == "alpha"
                expect(resultB?.stringValue) == "beta"
            }
        }
    }
}
