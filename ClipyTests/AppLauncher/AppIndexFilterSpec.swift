import Quick
import Nimble
@testable import Clipy

class AppIndexFilterSpec: QuickSpec {
    override func spec() {

        let mail = AppEntry(
            original: "Mail",
            cyr: AppIndex.translitLatinToCyrillic("Mail"),
            lat: "mail"
        )
        let terminal = AppEntry(
            original: "Terminal",
            cyr: AppIndex.translitLatinToCyrillic("Terminal"),
            lat: "terminal"
        )

        describe("AppIndex.matches") {

            context("Latin queries") {
                it("matches lowercase substring against original") {
                    expect(AppIndex.matches(terminal, query: "term")) == true
                }
                it("is case-insensitive — caller pre-lowers") {
                    expect(AppIndex.matches(terminal, query: "TERM".lowercased())) == true
                }
                it("misses when no index contains the substring") {
                    expect(AppIndex.matches(terminal, query: "browser")) == false
                }
            }

            context("Cyrillic transliteration matching") {
                it("matches the Russian-PC-layout transliteration of the name") {
                    // Mail in Russian-PC-layout = ьфшд
                    expect(AppIndex.matches(mail, query: "ьфшд")) == true
                }
                it("matches the uppercase Cyrillic query after lowercasing") {
                    let qlc = "ЬФШД".lowercased()
                    expect(AppIndex.matches(mail, query: qlc)) == true
                }
                it("matches a partial Cyrillic substring") {
                    expect(AppIndex.matches(mail, query: "ьф")) == true
                }
            }

            context("lat index") {
                it("matches a substring of the lowercase Latin name") {
                    expect(AppIndex.matches(mail, query: "mai")) == true
                }
            }
        }
    }
}
