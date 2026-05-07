import Quick
import Nimble
import Foundation
@testable import Clipy

class LegacyKeyedArchiveSpec: QuickSpec {
    override class func spec() {
        describe("LegacyKeyedArchive") {

            describe("archivedData / unarchivedObject(of:from:)") {

                it("round-trips a simple NSString") {
                    let original: NSString = "hello"
                    guard let data = LegacyKeyedArchive.archivedData(withRootObject: original) else {
                        fail("expected data"); return
                    }
                    expect(data.count) > 0
                    let decoded = LegacyKeyedArchive.unarchivedObject(of: NSString.self, from: data)
                    expect(decoded) == original
                }

                it("round-trips a CPYAppInfo (custom NSCoding type used in Exclude prefs)") {
                    let original = CPYAppInfo(info: [
                        kCFBundleIdentifierKey as String: "com.example.app" as AnyObject,
                        kCFBundleNameKey as String: "Example" as AnyObject
                    ])!
                    guard let data = LegacyKeyedArchive.archivedData(withRootObject: original) else {
                        fail("archive failed"); return
                    }
                    let decoded = LegacyKeyedArchive.unarchivedObject(of: CPYAppInfo.self, from: data)
                    expect(decoded?.identifier) == "com.example.app"
                    expect(decoded?.name) == "Example"
                }

                it("returns nil when decoding into the wrong type") {
                    let original: NSString = "hello"
                    let data = LegacyKeyedArchive.archivedData(withRootObject: original)!
                    expect(LegacyKeyedArchive.unarchivedObject(of: NSDate.self, from: data)).to(beNil())
                }

                it("returns nil for garbage data instead of throwing") {
                    let garbage = Data(repeating: 0xFF, count: 32)
                    expect(LegacyKeyedArchive.unarchivedObject(of: NSString.self, from: garbage)).to(beNil())
                }
            }

            describe("archiveRootObject(_:toFile:) / unarchivedObject(of:fromFile:)") {

                var tmpURL: URL!

                beforeEach {
                    tmpURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("LegacyKeyedArchiveSpec-\(UUID().uuidString).archive")
                }

                afterEach {
                    try? FileManager.default.removeItem(at: tmpURL)
                }

                it("writes a file and reads it back") {
                    let original = NSArray(array: ["a", "b", "c"])
                    let ok = LegacyKeyedArchive.archiveRootObject(original, toFile: tmpURL.path)
                    expect(ok) == true
                    expect(FileManager.default.fileExists(atPath: tmpURL.path)) == true

                    let decoded = LegacyKeyedArchive.unarchivedObject(of: NSArray.self, fromFile: tmpURL.path)
                    expect(decoded) == original
                }

                it("returns nil when the file is missing") {
                    let missing = "/tmp/definitely-not-here-\(UUID().uuidString)"
                    expect(LegacyKeyedArchive.unarchivedObject(of: NSString.self, fromFile: missing)).to(beNil())
                }

                it("returns false when the destination directory doesn't exist") {
                    let badPath = "/private/var/no-such-dir-\(UUID().uuidString)/file.archive"
                    expect(LegacyKeyedArchive.archiveRootObject("x" as NSString, toFile: badPath)) == false
                }
            }

            describe("NSCoding.archive() convenience") {
                it("matches archivedData(withRootObject:) byte-for-byte") {
                    let value: NSString = "hello"
                    let viaConvenience = value.archive()
                    let viaDirect = LegacyKeyedArchive.archivedData(withRootObject: value)
                    expect(viaConvenience).toNot(beNil())
                    expect(viaConvenience) == viaDirect
                }
            }

            describe("Array where Element: NSCoding archive() convenience") {
                it("archives an array of CPYAppInfo and round-trips it") {
                    let infos = [
                        CPYAppInfo(info: [
                            kCFBundleIdentifierKey as String: "com.a" as AnyObject,
                            kCFBundleNameKey as String: "A" as AnyObject
                        ])!,
                        CPYAppInfo(info: [
                            kCFBundleIdentifierKey as String: "com.b" as AnyObject,
                            kCFBundleNameKey as String: "B" as AnyObject
                        ])!
                    ]
                    let data = infos.archive()
                    expect(data).toNot(beNil())
                    let decoded = LegacyKeyedArchive.unarchivedObject(of: NSArray.self, from: data!)
                    expect(decoded?.count) == 2
                }
            }
        }
    }
}
