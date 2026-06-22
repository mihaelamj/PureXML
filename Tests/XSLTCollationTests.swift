import Testing
@testable import PureXML

/// Language-tailored `xsl:sort` collation orders (XSLTCollation.swift). These tables
/// were previously exercised only through the XSLT conformance golds; this gives them
/// standing coverage so `swift test` verifies the tailored orders directly.
@Suite("XSLT language collation (xsl:sort lang)")
struct XSLTCollationTests {
    private typealias Collation = PureXML.XSLT.Collation

    @Test("Polish ranks Ł between L and M, case-folded")
    func test_polish() throws {
        let ranks = try #require(Collation.table(for: "pl"))
        // L (U+004C) < Ł (U+0141) < M, the tailored order; under plain Unicode Ł
        // would sort after every ASCII letter, so this is the meaningful difference.
        #expect(Collation.compare("Lis", "Łoś", ranks) < 0)
        #expect(Collation.compare("Łoś", "Maj", ranks) < 0)
        // Diacritic letters interleave after their base: Ą after A, Ć after C.
        #expect(Collation.compare("Ananas", "Ćma", ranks) < 0)
        // Case-folded: lowercase ł shares Ł's rank, so it still sorts before m.
        #expect(Collation.compare("łoś", "maj", ranks) < 0)
    }

    @Test("Russian ranks Ё after Е, accepts a lang subtag")
    func test_russian() throws {
        // The primary subtag is honored, so `ru-RU` resolves to the Russian table.
        let ranks = try #require(Collation.table(for: "ru-RU"))
        #expect(Collation.compare("Е", "Ё", ranks) < 0)
        #expect(Collation.compare("Ё", "Ж", ranks) < 0)
    }

    @Test("an untabled language has no tailored order (nil)")
    func test_fallbackLanguages() {
        #expect(Collation.table(for: "en") == nil)
        #expect(Collation.table(for: "fr-CA") == nil)
        #expect(Collation.table(for: "") == nil)
    }

    @Test("compare orders by length then code point when ranks tie")
    func test_tieBreaks() throws {
        let ranks = try #require(Collation.table(for: "pl"))
        // A prefix sorts before the longer string sharing it.
        #expect(Collation.compare("Lis", "Lisek", ranks) < 0)
        #expect(Collation.compare("Lis", "Lis", ranks) == 0)
    }
}
