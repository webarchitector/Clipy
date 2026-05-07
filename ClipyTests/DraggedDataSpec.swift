import Quick
import Nimble
import Foundation
@testable import Clipy

class DraggedDataSpec: QuickSpec {
    override class func spec() {

        describe("NSCoding") {

            it("Archive data") {
                let draggedData = CPYDraggedData(type: .folder, folderIdentifier: UUID().uuidString, snippetIdentifier: nil, index: 10)
                let data = try NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: true)

                let unarchiveData = try NSKeyedUnarchiver.unarchivedObject(ofClass: CPYDraggedData.self, from: data)
                expect(unarchiveData).toNot(beNil())
                expect(unarchiveData?.type) == draggedData.type
                expect(unarchiveData?.folderIdentifier) == draggedData.folderIdentifier
                expect(unarchiveData?.snippetIdentifier).to(beNil())
                expect(unarchiveData?.index) == draggedData.index
            }

        }

    }
}
