import Testing
@testable import PureXML

@Suite("Regex Unicode categories and class subtraction")
struct RegexCategoryTests {
    private func matches(_ pattern: String, _ string: String) throws -> Bool {
        try PureXML.Regex.matches(pattern, string)
    }

    @Test("\\p{L} matches a letter group and rejects non-letters")
    func test_letterGroup() throws {
        #expect(try matches("\\p{L}+", "abcÅ"))
        #expect(try !matches("\\p{L}+", "ab1"))
    }

    @Test("\\p{Lu} and \\p{Ll} distinguish case")
    func test_caseCategories() throws {
        #expect(try matches("\\p{Lu}\\p{Ll}+", "Hello"))
        #expect(try !matches("\\p{Lu}\\p{Ll}+", "hello"))
    }

    @Test("\\p{Nd} matches decimal digits")
    func test_decimalNumber() throws {
        #expect(try matches("\\p{Nd}+", "2026"))
        #expect(try !matches("\\p{Nd}+", "12a"))
    }

    @Test("\\P{...} negates a category")
    func test_negatedCategory() throws {
        #expect(try matches("\\P{L}+", "123 !"))
        #expect(try !matches("\\P{L}+", "12a"))
    }

    @Test("A category inside a character class composes with ranges")
    func test_categoryInClass() throws {
        // A letter or an underscore.
        #expect(try matches("[\\p{L}_]+", "a_b"))
        #expect(try !matches("[\\p{L}_]+", "a-b"))
    }

    @Test("\\p{IsBasicLatin} tests a Unicode block")
    func test_block() throws {
        #expect(try matches("\\p{IsBasicLatin}+", "abc"))
        #expect(try !matches("\\p{IsBasicLatin}+", "abç"))
    }

    @Test("\\p{IsArabic} tests the Arabic block")
    func test_arabicBlock() throws {
        #expect(try matches("\\p{IsArabic}+", "\u{0627}\u{0628}"))
        // Adjacent Arabic block scalars that Swift fuses into one grapheme cluster.
        #expect(try matches("\\p{IsArabic}+", "\u{0600}\u{0601}"))
        // Base letter plus combining mark: two XSD characters, one grapheme.
        #expect(try matches("\\p{IsArabic}+", "\u{0627}\u{064B}"))
        #expect(try !matches("\\p{IsArabic}+", "abc"))
    }

    @Test("An unknown category name is a compile error")
    func test_unknownCategory() {
        #expect(throws: PureXML.Regex.RegexError.invalidProperty) {
            _ = try PureXML.Regex.Pattern("\\p{Zz}")
        }
        // An unknown Is<Block> name is rejected too (the block set is complete).
        #expect(throws: PureXML.Regex.RegexError.invalidProperty) {
            _ = try PureXML.Regex.Pattern("\\p{IsaA0-a9}")
        }
    }

    @Test("Supplementary-plane Is<Block> names match beyond the BMP")
    func test_supplementaryBlock() throws {
        // U+1D11E (musical symbol G clef) is in MusicalSymbols (1D100..1D1FF).
        #expect(try matches("\\p{IsMusicalSymbols}+", "\u{1D11E}"))
        #expect(try !matches("\\p{IsMusicalSymbols}+", "a"))
        // U+10300 (Old Italic letter A) is in OldItalic (10300..1032F).
        #expect(try matches("\\p{IsOldItalic}", "\u{10300}"))
    }

    @Test("Surrogate Is<Block> names compile but match no scalar")
    func test_surrogateBlockMatchesNothing() throws {
        // Lone surrogates are not Unicode scalars, so the block matches nothing,
        // but the name is valid XSD so the pattern still compiles (no false reject).
        #expect(try !matches("\\p{IsHighSurrogates}", "a"))
        #expect(try !matches("\\p{IsLowSurrogates}+", "\u{1D11E}"))
    }

    @Test("Character-class subtraction removes the subtrahend")
    func test_subtraction() throws {
        #expect(try matches("[a-z-[aeiou]]+", "bcdfg"))
        #expect(try !matches("[a-z-[aeiou]]+", "bce"))
    }

    @Test("A negated class with subtraction excludes both the base and the subtrahend")
    func test_negatedSubtraction() throws {
        // `[^cde-[ag]]` is (not c/d/e) minus a/g, i.e. excludes {a,c,d,e,g}
        // (XSD charClassSub: the difference of the NEGATED group and the
        // subtrahend). XSTS RegexTest_430: `agbfxyzga` contains a and g, so it
        // must NOT match `[^cde-[ag]]+`.
        #expect(try !matches("[^cde-[ag]]+", "agbfxyzga"))
        #expect(try matches("[^cde-[ag]]+", "bfxyz")) // none of a,c,d,e,g
        #expect(try !matches("[^cde-[ag]]+", "a")) // a is subtracted out
        #expect(try !matches("[^cde-[ag]]+", "c")) // c is in the negated base
        #expect(try matches("[^cde-[ag]]+", "b")) // b is admitted
    }

    @Test("Subtraction nests")
    func test_nestedSubtraction() throws {
        // a-z, minus (b-d minus c): so b and d are removed, c stays.
        #expect(try matches("[a-z-[b-d-[c]]]+", "acez"))
        #expect(try !matches("[a-z-[b-d-[c]]]+", "abz"))
    }

    @Test("Subtraction composes with a category subtrahend")
    func test_subtractCategory() throws {
        // Any letter that is not lowercase.
        #expect(try matches("[\\p{L}-[\\p{Ll}]]+", "ABC"))
        #expect(try !matches("[\\p{L}-[\\p{Ll}]]+", "ABc"))
    }
}
