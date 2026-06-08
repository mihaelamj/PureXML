@testable import PureXML
import Testing

@Suite("Regex")
struct RegexTests {
    private func matches(_ pattern: String, _ string: String) throws -> Bool {
        try PureXML.Regex.matches(pattern, string)
    }

    @Test("Literal patterns match the whole string")
    func test_literal() throws {
        #expect(try matches("abc", "abc"))
        #expect(try !matches("abc", "abcd"))
        #expect(try !matches("abc", "ab"))
    }

    @Test("The dot matches any character except line breaks")
    func test_dot() throws {
        #expect(try matches("a.c", "axc"))
        #expect(try !matches("a.c", "a\nc"))
    }

    @Test("Quantifiers ? * + bound repetition")
    func test_quantifiers() throws {
        #expect(try matches("ab?c", "ac"))
        #expect(try matches("ab?c", "abc"))
        #expect(try matches("ab*c", "abbbc"))
        #expect(try matches("ab+c", "abc"))
        #expect(try !matches("ab+c", "ac"))
    }

    @Test("Bounded quantifiers {n}, {n,}, {n,m}")
    func test_boundedQuantifiers() throws {
        #expect(try matches("a{3}", "aaa"))
        #expect(try !matches("a{3}", "aa"))
        #expect(try matches("a{2,}", "aaaa"))
        #expect(try matches("a{2,4}", "aaa"))
        #expect(try !matches("a{2,4}", "aaaaa"))
    }

    @Test("Alternation and grouping")
    func test_alternationGrouping() throws {
        #expect(try matches("cat|dog", "dog"))
        #expect(try matches("(ab)+", "ababab"))
        #expect(try matches("gr(a|e)y", "grey"))
        #expect(try !matches("gr(a|e)y", "groy"))
    }

    @Test("Character classes with ranges and negation")
    func test_charClasses() throws {
        #expect(try matches("[a-z]+", "hello"))
        #expect(try !matches("[a-z]+", "Hello"))
        #expect(try matches("[^0-9]+", "abc"))
        #expect(try matches("[abc]{2}", "ca"))
    }

    @Test("Class escapes \\d \\w \\s and their negations")
    func test_classEscapes() throws {
        #expect(try matches("\\d{4}", "2026"))
        #expect(try !matches("\\d{4}", "20x6"))
        #expect(try matches("\\w+", "a_1"))
        #expect(try matches("a\\sb", "a b"))
        #expect(try matches("\\D+", "abc"))
    }

    @Test("Escaped metacharacters are literal")
    func test_escapes() throws {
        #expect(try matches("a\\.b", "a.b"))
        #expect(try !matches("a\\.b", "axb"))
        #expect(try matches("\\(\\)", "()"))
    }

    @Test("A realistic ISBN-like pattern")
    func test_realistic() throws {
        let pattern = "\\d{3}-\\d{1,5}-\\d{1,7}-\\d{1,6}-[0-9X]"
        #expect(try matches(pattern, "978-0-13-468599-1"))
        #expect(try !matches(pattern, "abc-0-13-468599-1"))
    }

    @Test("Malformed patterns are rejected")
    func test_errors() {
        #expect(throws: PureXML.Regex.RegexError.self) { _ = try PureXML.Regex.Pattern("a(b") }
        #expect(throws: PureXML.Regex.RegexError.self) { _ = try PureXML.Regex.Pattern("*ab") }
        #expect(throws: PureXML.Regex.RegexError.self) { _ = try PureXML.Regex.Pattern("") }
    }
}
