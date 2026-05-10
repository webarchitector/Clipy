import Quick
import Nimble
import Foundation
import RealmSwift
import AEXML
@testable import Clipy

class SnippetXmlRoundTripSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        afterEach {
            let realm = try! Realm()
            try? realm.write { realm.deleteAll() }
        }

        describe("Old flat XML import (backward compat)") {
            it("imports a single-level folder with snippets and no nested folders element") {
                let xml = """
                <folders>
                  <folder>
                    <title>Greetings</title>
                    <snippets>
                      <snippet><title>hello</title><content>Hello, world!</content></snippet>
                    </snippets>
                  </folder>
                </folders>
                """
                let realm = try! Realm()
                try! realm.write { realm.deleteAll() }
                let imported = try SnippetXml.importDocument(data: xml.data(using: .utf8)!, into: realm, startingRootIndex: 0)
                expect(imported) == 1
                let folders = realm.objects(CPYFolder.self).filter("parentIdentifier == ''")
                expect(folders.count) == 1
                expect(folders.first?.title) == "Greetings"
                let snippets = realm.objects(CPYSnippet.self)
                expect(snippets.count) == 1
                expect(snippets.first?.parentIdentifier) == folders.first?.identifier
                expect(snippets.first?.title) == "hello"
                expect(snippets.first?.content) == "Hello, world!"
            }
        }

        describe("Round-trip with nesting") {
            it("export then import reproduces the same 3-level tree") {
                let realm = try! Realm()
                try! realm.write { realm.deleteAll() }

                let root = CPYFolder(); root.title = "Root1"; root.index = 0
                try! realm.write { realm.add(root) }
                let subA = CPYFolder(); subA.title = "SubA"; subA.parentIdentifier = root.identifier; subA.index = 0
                try! realm.write { realm.add(subA) }
                let snippetX = CPYSnippet(); snippetX.title = "x"; snippetX.content = "X"; snippetX.parentIdentifier = subA.identifier; snippetX.index = 0
                try! realm.write { realm.add(snippetX) }
                let subB = CPYFolder(); subB.title = "SubB"; subB.parentIdentifier = root.identifier; subB.index = 1
                try! realm.write { realm.add(subB) }
                let leafFolder = CPYFolder(); leafFolder.title = "Leaf"; leafFolder.parentIdentifier = subB.identifier; leafFolder.index = 0
                try! realm.write { realm.add(leafFolder) }
                let snippetY = CPYSnippet(); snippetY.title = "y"; snippetY.content = "Y"; snippetY.parentIdentifier = leafFolder.identifier; snippetY.index = 0
                try! realm.write { realm.add(snippetY) }

                let xmlData = SnippetXml.exportDocument(from: realm).xml.data(using: .utf8)!

                try! realm.write { realm.deleteAll() }
                _ = try SnippetXml.importDocument(data: xmlData, into: realm, startingRootIndex: 0)

                let roots = realm.objects(CPYFolder.self).filter("parentIdentifier == ''")
                expect(roots.count) == 1
                let importedRoot = roots.first!
                expect(importedRoot.title) == "Root1"
                let kids = CPYFolder.children(parentIdentifier: importedRoot.identifier, in: realm)
                expect(kids.count) == 2
                expect((kids[0] as? CPYFolder)?.title) == "SubA"
                expect((kids[1] as? CPYFolder)?.title) == "SubB"

                let aId = (kids[0] as? CPYFolder)?.identifier ?? ""
                let aKids = CPYFolder.children(parentIdentifier: aId, in: realm)
                expect(aKids.count) == 1
                expect((aKids[0] as? CPYSnippet)?.title) == "x"
                expect((aKids[0] as? CPYSnippet)?.content) == "X"

                let bId = (kids[1] as? CPYFolder)?.identifier ?? ""
                let bKids = CPYFolder.children(parentIdentifier: bId, in: realm)
                expect(bKids.count) == 1
                expect((bKids[0] as? CPYFolder)?.title) == "Leaf"

                let leafId = (bKids[0] as? CPYFolder)?.identifier ?? ""
                let leafKids = CPYFolder.children(parentIdentifier: leafId, in: realm)
                expect(leafKids.count) == 1
                expect((leafKids[0] as? CPYSnippet)?.title) == "y"
                expect((leafKids[0] as? CPYSnippet)?.content) == "Y"
            }
        }
    }
}
