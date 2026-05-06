import Quick
import Nimble
@testable import Clipy

class AppIndexTranslitSpec: QuickSpec {
    override func spec() {
        describe("translit tables") {

            it("maps lowercase Latin to lowercase Cyrillic via the Russian PC layout") {
                expect(AppIndex.latToCyr["t"]) == Character("е")
                expect(AppIndex.latToCyr["m"]) == Character("ь")
                expect(AppIndex.latToCyr["a"]) == Character("ф")
                expect(AppIndex.latToCyr["i"]) == Character("ш")
                expect(AppIndex.latToCyr["l"]) == Character("д")
            }

            it("maps both cases of Cyrillic to the same lowercase Latin") {
                expect(AppIndex.cyrToLat["Е"]) == Character("t")
                expect(AppIndex.cyrToLat["е"]) == Character("t")
                expect(AppIndex.cyrToLat["Ь"]) == Character("m")
                expect(AppIndex.cyrToLat["ь"]) == Character("m")
            }
        }

        describe("translitLatinToCyrillic") {

            it("renders an app's Latin name as Russian-PC-layout Cyrillic") {
                expect(AppIndex.translitLatinToCyrillic("Mail")) == "ьфшд"
                expect(AppIndex.translitLatinToCyrillic("Terminal")) == "еукьштфд"
                expect(AppIndex.translitLatinToCyrillic("Safari")) == "ыфафкш"
            }

            it("is lowercase regardless of input case") {
                expect(AppIndex.translitLatinToCyrillic("MAIL")) == "ьфшд"
            }

            it("passes characters that have no mapping through unchanged") {
                expect(AppIndex.translitLatinToCyrillic("Mail.app")) == "ьфшд.фзз"
                expect(AppIndex.translitLatinToCyrillic("a1b2")) == "ф1и2"
            }
        }

        describe("translitCyrillicToLatin") {

            it("converts both upper- and lower-case Cyrillic to lowercase Latin") {
                expect(AppIndex.translitCyrillicToLatin("ЬФШД")) == "MAIL".lowercased()
                expect(AppIndex.translitCyrillicToLatin("ьфшд")) == "mail"
            }

            it("passes Latin unchanged") {
                expect(AppIndex.translitCyrillicToLatin("usd")) == "usd"
            }
        }

        describe("round-trip") {

            it("Latin → Cyrillic → Latin preserves lowercased form") {
                let names = ["mail", "terminal", "safari"]
                for n in names {
                    let cy = AppIndex.translitLatinToCyrillic(n)
                    expect(AppIndex.translitCyrillicToLatin(cy)) == n
                }
            }
        }
    }
}
