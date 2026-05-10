import Quick
import Nimble
import Foundation
import RealmSwift
@testable import Clipy

class NestedDragDropSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        afterEach {
            let realm = try! Realm()
            try? realm.write { realm.deleteAll() }
        }

        describe("DropValidator (folder)") {

            it("rejects moving a folder onto itself") {
                let realm = try! Realm()
                let folder = CPYFolder(); folder.index = 0
                try! realm.write { realm.add(folder) }
                let result = DropValidator.validateFolderMove(movedId: folder.identifier, targetParentId: folder.identifier, in: realm)
                expect(result) == false
            }

            it("rejects moving a folder under one of its descendants (cycle)") {
                let realm = try! Realm()
                let parent = CPYFolder(); parent.index = 0
                try! realm.write { realm.add(parent) }
                let child = CPYFolder(); child.parentIdentifier = parent.identifier; child.index = 0
                try! realm.write { realm.add(child) }
                let result = DropValidator.validateFolderMove(movedId: parent.identifier, targetParentId: child.identifier, in: realm)
                expect(result) == false
            }

            it("rejects moves that would push depth above 5") {
                let realm = try! Realm()
                // Build a 4-deep chain: r1 -> r2 -> r3 -> r4
                var prev = ""
                var ids: [String] = []
                for _ in 0..<4 {
                    let folder = CPYFolder(); folder.parentIdentifier = prev; folder.index = 0
                    try! realm.write { realm.add(folder) }
                    prev = folder.identifier
                    ids.append(folder.identifier)
                }
                // A 2-level subtree: outer -> inner
                let outer = CPYFolder(); outer.index = 0
                try! realm.write { realm.add(outer) }
                let inner = CPYFolder(); inner.parentIdentifier = outer.identifier; inner.index = 0
                try! realm.write { realm.add(inner) }

                // Moving outer (height 2) under r4 (depth 4) → final deepest depth = 4 + 2 = 6, reject.
                let resultDeep = DropValidator.validateFolderMove(movedId: outer.identifier, targetParentId: ids[3], in: realm)
                expect(resultDeep) == false

                // Moving outer (height 2) under r3 (depth 3) → final deepest depth = 3 + 2 = 5, allow.
                let resultOK = DropValidator.validateFolderMove(movedId: outer.identifier, targetParentId: ids[2], in: realm)
                expect(resultOK) == true
            }

            it("allows valid folder moves") {
                let realm = try! Realm()
                let folderA = CPYFolder(); folderA.index = 0
                try! realm.write { realm.add(folderA) }
                let folderB = CPYFolder(); folderB.index = 1
                try! realm.write { realm.add(folderB) }
                let result = DropValidator.validateFolderMove(movedId: folderA.identifier, targetParentId: folderB.identifier, in: realm)
                expect(result) == true
            }
        }

        describe("DropValidator (snippet)") {

            it("rejects snippet moves to root") {
                let result = DropValidator.validateSnippetMove(targetParentId: "", in: try! Realm())
                expect(result) == false
            }

            it("allows snippet moves to any folder regardless of depth") {
                let realm = try! Realm()
                var prev = ""
                var ids: [String] = []
                for _ in 0..<5 {
                    let folder = CPYFolder(); folder.parentIdentifier = prev; folder.index = 0
                    try! realm.write { realm.add(folder) }
                    prev = folder.identifier
                    ids.append(folder.identifier)
                }
                expect(DropValidator.validateSnippetMove(targetParentId: ids[4], in: realm)) == true
            }
        }

        describe("Move execution") {

            it("moves a snippet across folders and renumbers both old and new parents") {
                let realm = try! Realm()
                let parent1 = CPYFolder(); parent1.index = 0
                let parent2 = CPYFolder(); parent2.index = 1
                try! realm.write { realm.add(parent1); realm.add(parent2) }

                let snippet1 = CPYSnippet(); snippet1.parentIdentifier = parent1.identifier; snippet1.index = 0
                let snippet2 = CPYSnippet(); snippet2.parentIdentifier = parent1.identifier; snippet2.index = 1
                try! realm.write { realm.add(snippet1); realm.add(snippet2) }

                try! realm.write {
                    NestedMoveExecutor.move(itemId: snippet1.identifier, isFolder: false,
                                            toParentId: parent2.identifier, atIndex: 0, in: realm)
                }
                expect(snippet1.parentIdentifier) == parent2.identifier
                expect(snippet1.index) == 0
                expect(snippet2.index) == 0
            }

            it("moves a folder and updates its parent without breaking the subtree") {
                let realm = try! Realm()
                let root1 = CPYFolder(); root1.index = 0
                let root2 = CPYFolder(); root2.index = 1
                try! realm.write { realm.add(root1); realm.add(root2) }

                let mid = CPYFolder(); mid.parentIdentifier = root1.identifier; mid.index = 0
                try! realm.write { realm.add(mid) }
                let leaf = CPYSnippet(); leaf.parentIdentifier = mid.identifier; leaf.index = 0
                try! realm.write { realm.add(leaf) }

                try! realm.write {
                    NestedMoveExecutor.move(itemId: mid.identifier, isFolder: true,
                                            toParentId: root2.identifier, atIndex: 0, in: realm)
                }
                expect(mid.parentIdentifier) == root2.identifier
                expect(leaf.parentIdentifier) == mid.identifier
                expect(leaf.index) == 0
            }
        }
    }
}
