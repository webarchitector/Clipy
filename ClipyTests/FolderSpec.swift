import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

// swiftlint:disable function_body_length
class FolderSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        describe("Create new") {

            it("deep copy object") {
                // Save Value
                let savedFolder = CPYFolder()
                savedFolder.index = 100
                savedFolder.title = "saved realm folder"

                let savedSnippet = CPYSnippet()
                savedSnippet.index = 10
                savedSnippet.title = "saved realm snippet"
                savedSnippet.content = "content"
                savedFolder.snippets.append(savedSnippet)

                let realm = try! Realm()
                realm.transaction { realm.add(savedFolder) }

                // Saved in Realm
                expect(savedFolder.realm).toNot(beNil())
                expect(savedSnippet.realm).toNot(beNil())

                // Deep copy
                let folder = savedFolder.deepCopy()
                expect(folder.realm).to(beNil())
                expect(folder.index) == savedFolder.index
                expect(folder.enable) == savedFolder.enable
                expect(folder.title) == savedFolder.title
                expect(folder.identifier) == savedFolder.identifier
                expect(folder.snippets.count) == 1

                let snippet = folder.snippets.first!
                expect(snippet.realm).to(beNil())
                expect(snippet.index) == savedSnippet.index
                expect(snippet.enable) == savedSnippet.enable
                expect(snippet.title) == savedSnippet.title
                expect(snippet.content) == savedSnippet.content
                expect(snippet.identifier) == savedSnippet.identifier
            }

            it("Create folder") {
                let folder = CPYFolder.create()
                expect(folder.title) == "untitled folder"
                expect(folder.index) == 0

                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                let folder2 = CPYFolder.create()
                expect(folder2.index) == 1
            }

            it("Create snippet") {
                let folder = CPYFolder()
                let snippet = folder.createSnippet()

                expect(snippet.title) == "untitled snippet"
                expect(snippet.index) == 0

                folder.snippets.append(snippet)

                let snippet2 = folder.createSnippet()
                expect(snippet2.index) == 1
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }

        }

        describe("Sync database") {

            it("Merge snippet") {
                let folder = CPYFolder()
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }
                let copyFolder = folder.deepCopy()

                let snippet = CPYSnippet()
                let snippet2 = CPYSnippet()
                copyFolder.mergeSnippet(snippet)
                copyFolder.mergeSnippet(snippet2)

                expect(snippet.realm).to(beNil())
                expect(snippet2.realm).to(beNil())
                expect(folder.snippets.count) == 2

                let savedSnippet = folder.snippets.first!
                let savedSnippet2 = folder.snippets[1]
                expect(savedSnippet.identifier) == snippet.identifier
                expect(savedSnippet2.identifier) == snippet2.identifier
            }

            it("Insert snippet") {
                let folder = CPYFolder()
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }
                let copyFolder = folder.deepCopy()

                let snippet = CPYSnippet()
                // Don't insert non saved snippt
                copyFolder.insertSnippet(snippet, index: 0)
                expect(folder.snippets.count) == 0

                realm.transaction { realm.add(snippet) }

                // Can insert saved snippet
                copyFolder.insertSnippet(snippet, index: 0)
                expect(folder.snippets.count) == 1
            }

            it("Remove snippet") {
                let folder = CPYFolder()
                let snippet = CPYSnippet()
                folder.snippets.append(snippet)
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                expect(folder.snippets.count) == 1

                let copyFolder = folder.deepCopy()
                copyFolder.removeSnippet(snippet)

                expect(folder.snippets.count) == 0
            }

            it("Merge folder") {
                let realm = try! Realm()
                expect(realm.objects(CPYFolder.self).count) == 0

                let folder = CPYFolder()
                folder.index = 100
                folder.title = "title"
                folder.enable = false
                folder.merge()
                expect(folder.realm).to(beNil())
                expect(realm.objects(CPYFolder.self).count) == 1

                let savedFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.identifier)
                expect(savedFolder).toNot(beNil())
                expect(savedFolder?.index) == folder.index
                expect(savedFolder?.title) == folder.title
                expect(savedFolder?.enable) == folder.enable

                folder.index = 1
                folder.title = "change title"
                folder.enable = true
                folder.merge()
                expect(realm.objects(CPYFolder.self).count) == 1

                expect(savedFolder?.index) == folder.index
                expect(savedFolder?.title) == folder.title
                expect(savedFolder?.enable) == folder.enable
            }

            it("Remove folder") {
                let folder = CPYFolder()
                let snippet = CPYSnippet()
                folder.snippets.append(snippet)
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                expect(realm.objects(CPYFolder.self).count) == 1
                expect(realm.objects(CPYSnippet.self).count) == 1

                let copyFolder = folder.deepCopy()
                expect(copyFolder.realm).to(beNil())
                copyFolder.remove()

                expect(realm.objects(CPYFolder.self).count) == 0
                expect(realm.objects(CPYSnippet.self).count) == 0
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }

        }

        describe("Rearrange Index") {

            it("Rearrange folder index") {
                let folder = CPYFolder()
                folder.index = 100
                let folder2 = CPYFolder()
                folder2.index = 10

                let folders = [folder, folder2]
                let realm = try! Realm()
                realm.transaction { realm.add(folders) }

                let copyFolder = folder.deepCopy()
                let copyFolder2 = folder2.deepCopy()

                CPYFolder.rearrangesIndex([copyFolder, copyFolder2])

                expect(copyFolder.index) == 0
                expect(copyFolder2.index) == 1
                expect(folder.index) == 0
                expect(folder2.index) == 1
            }

            it("Rearrange snippet index") {
                let folder = CPYFolder()
                let snippet = CPYSnippet()
                snippet.index = 10
                let snippet2 = CPYSnippet()
                snippet2.index = 100
                folder.snippets.append(snippet)
                folder.snippets.append(snippet2)
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                let copyFolder = folder.deepCopy()
                copyFolder.rearrangesSnippetIndex()

                let copySnippet = copyFolder.snippets.first!
                let copySnippet2 = copyFolder.snippets[1]
                expect(copySnippet.index) == 0
                expect(copySnippet2.index) == 1
                expect(snippet.index) == 0
                expect(snippet2.index) == 1
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }

        }

        describe("Tree helpers (parentIdentifier model)") {

            it("children(of:) merges folders and snippets sorted by index") {
                let realm = try! Realm()
                let parent = CPYFolder()
                parent.title = "P"; parent.index = 0
                realm.transaction { realm.add(parent) }

                let snippet = CPYSnippet()
                snippet.title = "snippet"; snippet.index = 1
                snippet.parentIdentifier = parent.identifier

                let subfolder = CPYFolder()
                subfolder.title = "sub"; subfolder.index = 0
                subfolder.parentIdentifier = parent.identifier

                let snippet2 = CPYSnippet()
                snippet2.title = "snippet2"; snippet2.index = 2
                snippet2.parentIdentifier = parent.identifier

                realm.transaction {
                    realm.add(snippet); realm.add(subfolder); realm.add(snippet2)
                }

                let kids = CPYFolder.children(parentIdentifier: parent.identifier, in: realm)
                expect(kids.count) == 3
                expect((kids[0] as? CPYFolder)?.title) == "sub"
                expect((kids[1] as? CPYSnippet)?.title) == "snippet"
                expect((kids[2] as? CPYSnippet)?.title) == "snippet2"
            }

            it("depth(of:) returns 1 for a root folder, N for an N-deep folder") {
                let realm = try! Realm()
                var prevID = ""
                var folders: [CPYFolder] = []
                for level in 0..<5 {
                    let folder = CPYFolder(); folder.title = "L\(level + 1)"; folder.index = 0
                    folder.parentIdentifier = prevID
                    realm.transaction { realm.add(folder) }
                    folders.append(folder)
                    prevID = folder.identifier
                }
                expect(CPYFolder.depth(of: folders[0], in: realm)) == 1
                expect(CPYFolder.depth(of: folders[1], in: realm)) == 2
                expect(CPYFolder.depth(of: folders[4], in: realm)) == 5
            }

            it("maxDescendantDepth(of:) returns 1 for a leaf folder, N for an N-level subtree") {
                let realm = try! Realm()
                let root = CPYFolder(); root.title = "R"; root.index = 0
                realm.transaction { realm.add(root) }
                expect(CPYFolder.maxDescendantDepth(of: root, in: realm)) == 1

                let mid = CPYFolder(); mid.title = "A"; mid.index = 0; mid.parentIdentifier = root.identifier
                realm.transaction { realm.add(mid) }
                expect(CPYFolder.maxDescendantDepth(of: root, in: realm)) == 2

                let leaf = CPYFolder(); leaf.title = "B"; leaf.index = 0; leaf.parentIdentifier = mid.identifier
                realm.transaction { realm.add(leaf) }
                expect(CPYFolder.maxDescendantDepth(of: root, in: realm)) == 3
                expect(CPYFolder.maxDescendantDepth(of: mid, in: realm)) == 2
            }

            it("isDescendant(_:of:) detects ancestry up to root") {
                let realm = try! Realm()
                let root = CPYFolder(); root.index = 0
                realm.transaction { realm.add(root) }
                let mid = CPYFolder(); mid.index = 0; mid.parentIdentifier = root.identifier
                realm.transaction { realm.add(mid) }
                let leaf = CPYFolder(); leaf.index = 0; leaf.parentIdentifier = mid.identifier
                realm.transaction { realm.add(leaf) }

                expect(CPYFolder.isDescendant(leaf, of: root, in: realm)) == true
                expect(CPYFolder.isDescendant(leaf, of: mid, in: realm)) == true
                expect(CPYFolder.isDescendant(mid, of: leaf, in: realm)) == false
                expect(CPYFolder.isDescendant(root, of: root, in: realm)) == false
            }

            it("renumberSiblings(of:) assigns 0..n-1 in current index order across mixed children") {
                let realm = try! Realm()
                let parent = CPYFolder(); parent.index = 0
                realm.transaction { realm.add(parent) }

                let folder1 = CPYFolder(); folder1.parentIdentifier = parent.identifier; folder1.index = 100
                let snippet1 = CPYSnippet(); snippet1.parentIdentifier = parent.identifier; snippet1.index = 50
                let folder2 = CPYFolder(); folder2.parentIdentifier = parent.identifier; folder2.index = 200
                realm.transaction { realm.add(folder1); realm.add(snippet1); realm.add(folder2) }

                CPYFolder.renumberSiblings(of: parent.identifier, in: realm)

                expect(snippet1.index) == 0
                expect(folder1.index) == 1
                expect(folder2.index) == 2
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }
        }

    }
}
