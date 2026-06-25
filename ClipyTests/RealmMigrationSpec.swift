import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class RealmMigrationSpec: QuickSpec {
    override class func spec() {
        describe("Realm.migration()") {

            beforeEach {
                // Reset to a fresh in-memory default so each test below
                // installs the migration on a clean slate.
                Realm.Configuration.defaultConfiguration = Realm.Configuration()
                Realm.Configuration.defaultConfiguration.inMemoryIdentifier = UUID().uuidString
            }

            it("installs schemaVersion 10 onto the default configuration") {
                Realm.migration()
                expect(Realm.Configuration.defaultConfiguration.schemaVersion) == 10
            }

            it("installs a migration block (non-nil)") {
                Realm.migration()
                expect(Realm.Configuration.defaultConfiguration.migrationBlock) != nil
            }

            it("installs shouldCompactOnLaunch") {
                Realm.migration()
                expect(Realm.Configuration.defaultConfiguration.shouldCompactOnLaunch) != nil
            }

            it("compaction predicate triggers above 100 MB and below 50% usage") {
                Realm.migration()
                guard let predicate = Realm.Configuration.defaultConfiguration.shouldCompactOnLaunch else {
                    fail("shouldCompactOnLaunch missing"); return
                }
                let oneHundredMB = 100 * 1024 * 1024
                // Above 100 MB and < 50% used → compact
                expect(predicate(oneHundredMB + 1, (oneHundredMB + 1) / 4)) == true
                // Above 100 MB but >= 50% used → don't compact
                expect(predicate(oneHundredMB + 1, oneHundredMB)) == false
                // Below or equal to 100 MB → don't compact regardless of usage
                expect(predicate(oneHundredMB, 0)) == false
                expect(predicate(50 * 1024 * 1024, 1024)) == false
            }

            it("opens a fresh realm at the new schema version without invoking the migration block") {
                // No prior file → migration block must not be called.
                var migrationFired = false
                let probeConfig = Realm.Configuration(
                    inMemoryIdentifier: UUID().uuidString,
                    schemaVersion: 8,
                    migrationBlock: { _, _ in migrationFired = true }
                )
                _ = try? Realm(configuration: probeConfig)
                expect(migrationFired) == false
            }

            describe("Snippet parentIdentifier backfill") {
                it("maps snippets to their containing folder identifier") {
                    let folderA = "folder-A"
                    let folderB = "folder-B"
                    let snippetsByFolder: [String: [String]] = [
                        folderA: ["s1", "s2"],
                        folderB: ["s3"]
                    ]
                    let map = SnippetParentBackfill.parentMap(folders: snippetsByFolder)
                    expect(map.count) == 3
                    expect(map["s1"]) == folderA
                    expect(map["s2"]) == folderA
                    expect(map["s3"]) == folderB
                }

                it("orphan snippets (not in any folder) get an empty parent") {
                    let map = SnippetParentBackfill.parentMap(folders: ["fA": ["s1"]])
                    expect(SnippetParentBackfill.parentFor(snippetId: "missing", in: map)) == ""
                    expect(SnippetParentBackfill.parentFor(snippetId: "s1", in: map)) == "fA"
                }
            }

            it("supports the current schema (CPYClip / CPYFolder / CPYSnippet) on a fresh realm") {
                Realm.migration()
                // Force in-memory so this test doesn't see / contaminate the
                // user's actual Realm file (Realm.migration() resets the
                // default config to disk-backed).
                Realm.Configuration.defaultConfiguration.inMemoryIdentifier = UUID().uuidString
                let realm = try? Realm()
                expect(realm) != nil

                guard let realm = realm else { return }

                let folderCountBefore = realm.objects(CPYFolder.self).count
                let snippetCountBefore = realm.objects(CPYSnippet.self).count
                let clipCountBefore = realm.objects(CPYClip.self).count

                // Smoke: write one of each core model and read back. If the
                // migration left the schema in a bad state, write/read fails.
                try? realm.write {
                    let folder = CPYFolder()
                    folder.title = "test folder"
                    folder.index = 0
                    let snippet = CPYSnippet()
                    snippet.title = "test snippet"
                    snippet.content = "snippet content"
                    snippet.index = 0
                    let clip = CPYClip()
                    clip.title = "test clip"
                    clip.dataPath = "/tmp/test.data"
                    clip.dataHash = UUID().uuidString
                    clip.primaryType = "public.utf8-plain-text"
                    clip.updateTime = Int(Date().timeIntervalSince1970)
                    realm.add(folder)
                    realm.add(snippet)
                    realm.add(clip)
                }
                expect(realm.objects(CPYFolder.self).count) == folderCountBefore + 1
                expect(realm.objects(CPYSnippet.self).count) == snippetCountBefore + 1
                expect(realm.objects(CPYClip.self).count) == clipCountBefore + 1
                expect(realm.objects(CPYFolder.self).last?.identifier) != nil
                expect(realm.objects(CPYSnippet.self).last?.identifier) != nil
            }
        }
    }
}
