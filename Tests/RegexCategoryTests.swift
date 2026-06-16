@testable import PureXML
import Testing

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
        #expect(throws: PureXML.Regex.RegexError.self) {
            _ = try PureXML.Regex.Pattern("\\p{Zz}")
        }
    }

    @Test("Character-class subtraction removes the subtrahend")
    func test_subtraction() throws {
        #expect(try matches("[a-z-[aeiou]]+", "bcdfg"))
        #expect(try !matches("[a-z-[aeiou]]+", "bce"))
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
