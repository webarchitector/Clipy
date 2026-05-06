import Quick
import Nimble
@testable import Clipy

class InputSourceServiceDedupSpec: QuickSpec {
    override func spec() {
        describe("InputSourceService.dedupCombos") {

            it("returns an empty list for empty input") {
                let result = InputSourceService.dedupCombos([] as [(identifier: String, combo: Int?)])
                expect(result).to(beEmpty())
            }

            it("keeps every entry when no combos collide") {
                let result = InputSourceService.dedupCombos([
                    (identifier: "src.a", combo: 10),
                    (identifier: "src.b", combo: 20),
                    (identifier: "src.c", combo: 30)
                ])
                expect(result.count) == 3
                expect(result.map { $0.combo }) == [10, 20, 30]
                expect(result.allSatisfy { !$0.droppedAsDuplicate }) == true
            }

            it("clears the second entry when its combo matches an earlier one") {
                let result = InputSourceService.dedupCombos([
                    (identifier: "src.a", combo: 10),
                    (identifier: "src.b", combo: 10)
                ])
                expect(result[0].combo) == 10
                expect(result[0].droppedAsDuplicate) == false
                expect(result[1].combo).to(beNil())
                expect(result[1].droppedAsDuplicate) == true
            }

            it("drops every later occurrence of a combo, not just the second") {
                let result = InputSourceService.dedupCombos([
                    (identifier: "src.a", combo: 7),
                    (identifier: "src.b", combo: 7),
                    (identifier: "src.c", combo: 7)
                ])
                expect(result.map { $0.combo }) == [7, nil, nil]
                expect(result.map { $0.droppedAsDuplicate }) == [false, true, true]
            }

            it("passes nil combos through unchanged and never treats them as duplicates") {
                let result = InputSourceService.dedupCombos([
                    (identifier: "src.a", combo: nil),
                    (identifier: "src.b", combo: 5),
                    (identifier: "src.c", combo: nil),
                    (identifier: "src.d", combo: 5)
                ])
                expect(result.map { $0.combo }) == [nil, 5, nil, nil]
                expect(result.map { $0.droppedAsDuplicate }) == [false, false, false, true]
            }

            it("preserves the original order of identifiers") {
                let entries: [(identifier: String, combo: Int?)] = [
                    (identifier: "id3", combo: 1),
                    (identifier: "id1", combo: 2),
                    (identifier: "id2", combo: 1)
                ]
                let result = InputSourceService.dedupCombos(entries)
                expect(result.map { $0.identifier }) == ["id3", "id1", "id2"]
            }
        }
    }
}
