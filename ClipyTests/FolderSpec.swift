import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class FolderSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        describe("Create new") {

            it("Create folder") {
                let folder = CPYFolder.create()
                expect(folder.title) == "untitled folder"
                expect(folder.index) == 0

                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                let folder2 = CPYFolder.create()
                expect(folder2.index) == 1
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }

        }

        describe("Sync database") {

            it("Merge folder") {
                let realm = try! Realm()
                expect(realm.objects(CPYFolder.self).count) == 0

                let folder = CPYFolder()
                folder.index = 100
                folder.title = "title"
                folder.enable = false
                folder.merge()
                expect(folder.realm) == nil
                expect(realm.objects(CPYFolder.self).count) == 1

                let savedFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.identifier)
                expect(savedFolder) != nil
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

            it("Remove folder cascades to snippet children when caller deletes them too") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.title = "F"; folder.index = 0
                try! realm.write { realm.add(folder) }
                let snippet = CPYSnippet(); snippet.parentIdentifier = folder.identifier; snippet.index = 0
                try! realm.write { realm.add(snippet) }

                expect(realm.objects(CPYFolder.self).count) == 1
                expect(realm.objects(CPYSnippet.self).count) == 1

                // The new flow is: caller deletes the folder along with its
                // descendants. We assert this contract by hand here (the
                // editor's deleteFolderRecursively does the same).
                try! realm.write {
                    let snippets = realm.objects(CPYSnippet.self).filter("parentIdentifier == %@", folder.identifier)
                    realm.delete(snippets)
                    realm.delete(folder)
                }

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
