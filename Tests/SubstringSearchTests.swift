import Testing
@testable import PureXML

/// `contains`, `substring-before`, and `substring-after` locate the needle
/// through a linear-time (KMP) search rather than matching at every position
/// (which is quadratic on a repetitive string). These pin the search semantics:
/// found at the start/middle/end, not found, overlapping repeats, and the empty
/// needle, plus a repetitive case that the naive search would have made slow.
@Suite("substring search functions")
struct SubstringSearchTests {
    private func string(_ expression: String) throws -> String {
        try PureXML.XPath.Query(expression).value(at: PureXML.parseTree("<r/>")).string
    }

    private func boolean(_ expression: String) throws -> Bool {
        try PureXML.XPath.Query(expression).value(at: PureXML.parseTree("<r/>")).boolean
    }

    @Test("contains finds the needle anywhere, or reports its absence")
    func test_contains() throws {
        #expect(try boolean("contains('hello world', 'world')"))
        #expect(try boolean("contains('hello world', 'hello')"))
        #expect(try boolean("contains('hello world', 'o w')"))
        #expect(try !boolean("contains('hello', 'xyz')"))
        #expect(try boolean("contains('hello', '')"))
        // Overlapping repeats: the match starts at the first valid position.
        #expect(try boolean("contains('aaaa', 'aaa')"))
        #expect(try !boolean("contains('aaa', 'aaaa')"))
    }

    @Test("substring-before and substring-after split at the first occurrence")
    func test_split() throws {
        #expect(try string("substring-before('1999/04/01', '/')") == "1999")
        #expect(try string("substring-after('1999/04/01', '/')") == "04/01")
        #expect(try string("substring-before('a-b-c', '-')") == "a")
        #expect(try string("substring-after('a-b-c', '-')") == "b-c")
        // Needle absent: both return the empty string (XPath 1.0).
        #expect(try string("substring-before('abc', 'x')") == "")
        #expect(try string("substring-after('abc', 'x')") == "")
    }

    @Test("the search is correct on a repetitive string the naive scan made slow")
    func test_repetitive() throws {
        let haystack = String(repeating: "a", count: 500) + "b"
        // 'a...ab' (the whole string) is present once, at the start.
        #expect(try boolean("contains('\(haystack)', '\(haystack)')"))
        // 'a...a' + 'c' is absent; the search must report false without rescanning.
        let absent = String(repeating: "a", count: 400) + "c"
        #expect(try !boolean("contains('\(haystack)', '\(absent)')"))
        #expect(try string("substring-after('\(haystack)', 'b')") == "")
    }
}
