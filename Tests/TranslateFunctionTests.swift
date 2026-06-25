import Testing
@testable import PureXML

/// `translate(string, from, to)` builds its from-to map once for an O(1) lookup
/// per source character instead of scanning `from` per character. These pin the
/// XPath 1.0 semantics it must preserve: positional replacement, deletion when a
/// from-character has no positional replacement, first-occurrence-wins for a
/// repeated from-character, and pass-through for characters not in `from`.
@Suite("translate function")
struct TranslateFunctionTests {
    private func translate(_ source: String, _ from: String, _ target: String) throws -> String {
        let escaped = { (text: String) in text.replacingOccurrences(of: "'", with: "&apos;") }
        let query = "translate('\(escaped(source))', '\(escaped(from))', '\(escaped(target))')"
        return try PureXML.XPath.Query(query).value(at: PureXML.parseTree("<r/>")).string
    }

    private func scalars(_ base: Int, _ count: Int) -> String {
        String((0 ..< count).compactMap { UnicodeScalar(base + $0).map(Character.init) })
    }

    @Test("positional replacement and pass-through")
    func test_replace() throws {
        #expect(try translate("bar", "abc", "ABC") == "BAr")
        #expect(try translate("abcdef", "abc", "xyz") == "xyzdef")
        #expect(try translate("hello", "", "") == "hello")
    }

    @Test("a from-character with no positional replacement is deleted")
    func test_delete() throws {
        // The classic spec example: '-' has no replacement, so it is removed.
        #expect(try translate("--aaa--", "abc-", "ABC") == "AAA")
        #expect(try translate("abc", "abc", "x") == "x")
        #expect(try translate("a1b2c3", "123", "") == "abc")
    }

    @Test("the first occurrence of a repeated from-character wins")
    func test_firstOccurrenceWins() throws {
        // Second 'a' in `from` is ignored: 'a' maps to the index-0 replacement.
        #expect(try translate("abc", "aba", "XYZ") == "XYc")
        // First occurrence is a deletion (no positional replacement); the later
        // occurrence that would replace is ignored.
        #expect(try translate("ab", "aa", "X") == "Xb")
    }

    @Test("translating a long string with a large map is correct")
    func test_largeMap() throws {
        // The quadratic-prone case made fast: many distinct characters mapped.
        let source = scalars(0x100, 300)
        let target = scalars(0x101, 300)
        #expect(try translate(source, source, target) == target)
    }
}
