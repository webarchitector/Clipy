import Quick
import Nimble
import Foundation
@testable import Clipy

class DraggedDataSpec: QuickSpec {
    override class func spec() {

        describe("NSCoding") {

            it("Archive folder data") {
                let id = UUID().uuidString
                let parent = UUID().uuidString
                let draggedData = CPYDraggedData(type: .folder, identifier: id, parentIdentifier: parent, index: 10)
                let data = try NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: true)

                let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: CPYDraggedData.self, from: data)
                expect(unarchived).toNot(beNil())
                expect(unarchived?.type) == draggedData.type
                expect(unarchived?.identifier) == id
                expect(unarchived?.parentIdentifier) == parent
                expect(unarchived?.index) == 10
            }

            it("Archive snippet data with empty parent string is preserved") {
                // Snippets always have a non-empty parentIdentifier; we still
                // verify the empty-string round-trip for safety.
                let draggedData = CPYDraggedData(type: .snippet, identifier: "s", parentIdentifier: "", index: 0)
                let data = try NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: true)
                let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: CPYDraggedData.self, from: data)
                expect(unarchived?.parentIdentifier) == ""
                expect(unarchived?.identifier) == "s"
            }
        }
    }
}
