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

        describe("parseTree") {
            it("root-only folder with notes") {
                let rs = "\u{1D}"
                let fs = "\u{1E}"
                let raw = "F\(fs)Root\(rs)N\(fs)Root\(fs)NoteA\(fs)Hello world\(rs)"
                let node = NotesOutputParser.parseTree(raw, rootFolderName: "Root")
                expect(node.title) == "Root"
                expect(node.subfolders).to(beEmpty())
                expect(node.snippets.count) == 1
                expect(node.snippets[0].title) == "NoteA"
                expect(node.snippets[0].content) == "Hello world"
            }

            it("one subfolder with a note alongside root notes") {
                let rs = "\u{1D}"
                let fs = "\u{1E}"
                let ps = "\u{1F}"
                let raw = """
                F\(fs)Root\(rs)\
                N\(fs)Root\(fs)RootNote\(fs)Root content\(rs)\
                F\(fs)Root\(ps)Sub\(rs)\
                N\(fs)Root\(ps)Sub\(fs)SubNote\(fs)Sub content\(rs)
                """
                let node = NotesOutputParser.parseTree(raw, rootFolderName: "Root")
                expect(node.title) == "Root"
                expect(node.snippets.count) == 1
                expect(node.snippets[0].title) == "RootNote"
                expect(node.snippets[0].content) == "Root content"
                expect(node.subfolders.count) == 1
                let sub = node.subfolders[0]
                expect(sub.title) == "Sub"
                expect(sub.snippets.count) == 1
                expect(sub.snippets[0].title) == "SubNote"
                expect(sub.snippets[0].content) == "Sub content"
            }

            it("two-level nesting: root > A > B with note in B") {
                let rs = "\u{1D}"
                let fs = "\u{1E}"
                let ps = "\u{1F}"
                let raw = """
                F\(fs)Root\(rs)\
                F\(fs)Root\(ps)A\(rs)\
                F\(fs)Root\(ps)A\(ps)B\(rs)\
                N\(fs)Root\(ps)A\(ps)B\(fs)DeepNote\(fs)Deep content\(rs)
                """
                let node = NotesOutputParser.parseTree(raw, rootFolderName: "Root")
                expect(node.subfolders.count) == 1
                let folderA = node.subfolders[0]
                expect(folderA.title) == "A"
                expect(folderA.snippets).to(beEmpty())
                expect(folderA.subfolders.count) == 1
                let folderB = folderA.subfolders[0]
                expect(folderB.title) == "B"
                expect(folderB.snippets.count) == 1
                expect(folderB.snippets[0].title) == "DeepNote"
                expect(folderB.snippets[0].content) == "Deep content"
            }

            it("empty subfolder (F record with no notes) is present in the tree") {
                let rs = "\u{1D}"
                let fs = "\u{1E}"
                let ps = "\u{1F}"
                let raw = "F\(fs)Root\(rs)F\(fs)Root\(ps)EmptyFolder\(rs)"
                let node = NotesOutputParser.parseTree(raw, rootFolderName: "Root")
                expect(node.snippets).to(beEmpty())
                expect(node.subfolders.count) == 1
                let empty = node.subfolders[0]
                expect(empty.title) == "EmptyFolder"
                expect(empty.snippets).to(beEmpty())
                expect(empty.subfolders).to(beEmpty())
            }

            it("note content containing a newline is preserved intact") {
                let rs = "\u{1D}"
                let fs = "\u{1E}"
                let raw = "F\(fs)Root\(rs)N\(fs)Root\(fs)MultiLine\(fs)Line1\nLine2\(rs)"
                let node = NotesOutputParser.parseTree(raw, rootFolderName: "Root")
                expect(node.snippets.count) == 1
                expect(node.snippets[0].title) == "MultiLine"
                expect(node.snippets[0].content) == "Line1\nLine2"
            }

            it("creates intermediate folder nodes for paths with missing F records") {
                let rs = "\u{1D}"
                let fs = "\u{1E}"
                let ps = "\u{1F}"
                // Only a deep note record — A and B folders implied by the parent path
                let raw = "N\(fs)Root\(ps)A\(ps)B\(fs)ImpliedNote\(fs)Implied content\(rs)"
                let node = NotesOutputParser.parseTree(raw, rootFolderName: "Root")
                expect(node.subfolders.count) == 1
                let folderA = node.subfolders[0]
                expect(folderA.title) == "A"
                expect(folderA.subfolders.count) == 1
                let folderB = folderA.subfolders[0]
                expect(folderB.title) == "B"
                expect(folderB.snippets.count) == 1
                expect(folderB.snippets[0].title) == "ImpliedNote"
            }

            it("returns root-named empty node for completely empty output") {
                let node = NotesOutputParser.parseTree("", rootFolderName: "Empty")
                expect(node.title) == "Empty"
                expect(node.snippets).to(beEmpty())
                expect(node.subfolders).to(beEmpty())
            }
        }
    }
}
