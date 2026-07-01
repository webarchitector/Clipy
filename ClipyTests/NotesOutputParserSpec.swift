import Quick
import Nimble
import Foundation
@testable import Clipy

class NotesOutputParserSpec: QuickSpec {
    override class func spec() {
        describe("parseFolderNames") {
            it("splits newline-delimited folder names and trims blanks") {
                let raw = "Notes\nSnippets\n\nWork\n"
                expect(NotesOutputParser.parseFolderNames(raw)) == ["Notes", "Snippets", "Work"]
            }
        }

        describe("parseNotes") {
            it("builds a folder node with title+content pairs") {
                let rs = "\u{1D}"
                let fs = "\u{1E}"
                let raw = "hello\(fs)Hello, world!\(rs)sig\(fs)Best,\nAnk"
                let node = NotesOutputParser.parseNotes(raw, folderName: "Snippets")
                expect(node.title) == "Snippets"
                expect(node.subfolders).to(beEmpty())
                expect(node.snippets.count) == 2
                expect(node.snippets[0]) == NotesSnippetNode(title: "hello", content: "Hello, world!")
                expect(node.snippets[1]) == NotesSnippetNode(title: "sig", content: "Best,\nAnk")
            }

            it("returns an empty folder for empty output") {
                let node = NotesOutputParser.parseNotes("", folderName: "Empty")
                expect(node.title) == "Empty"
                expect(node.snippets).to(beEmpty())
            }
        }
    }
}
