import Testing
@testable import PureXML

/// The escaping functions take a fast path that returns the value unchanged when
/// nothing needs escaping, and the original character-by-character path when
/// something does. These tests pin both: a value with no escapable character
/// must round-trip identically (and, being the fast path, be the same instance's
/// content), and a value with an escapable character must still be escaped.
@Suite("Escaping fast-path equivalence")
struct EscapingFastPathTests {
    private typealias Escaping = PureXML.Emitting.Escaping

    @Test("text: plain content is unchanged, markup is escaped")
    func test_text() {
        #expect(Escaping.text("plain content, no markup") == "plain content, no markup")
        #expect(Escaping.text("a & b < c > d") == "a &amp; b &lt; c &gt; d")
        #expect(Escaping.text("café résumé") == "café résumé")
        // ASCII-only escapes non-ASCII even with no markup character.
        #expect(Escaping.text("café", asciiOnly: true) == "caf&#xE9;")
        // A carriage return is escaped only when asked.
        #expect(Escaping.text("a\rb") == "a\rb")
        #expect(Escaping.text("a\rb", escapeCarriageReturn: true) == "a&#xD;b")
    }

    @Test("attribute: plain value is unchanged, specials are escaped")
    func test_attribute() {
        #expect(Escaping.attribute("plain value") == "plain value")
        #expect(Escaping.attribute("a \"q\" b") == "a &quot;q&quot; b")
        // The inactive quote is not escaped.
        #expect(Escaping.attribute("it's fine", quote: "\"") == "it's fine")
        #expect(Escaping.attribute("it's fine", quote: "'") == "it&apos;s fine")
        #expect(Escaping.attribute("x\ty\nz") == "x&#9;y&#10;z")
        #expect(Escaping.attribute("a & b < c") == "a &amp; b &lt; c")
        #expect(Escaping.attribute("ñ", asciiOnly: true) == "&#xF1;")
    }

    @Test("comment: hyphen-free is unchanged, -- gets a separating space")
    func test_comment() {
        #expect(Escaping.comment("a plain comment") == "a plain comment")
        #expect(Escaping.comment("single - hyphen is fine") == "single - hyphen is fine")
        #expect(Escaping.comment("bad -- pair") == "bad - - pair")
        #expect(Escaping.comment("trailing-") == "trailing- ")
    }

    @Test("processing instruction: question-free is unchanged, ?> gets a space")
    func test_processingInstruction() {
        #expect(Escaping.processingInstruction("plain data") == "plain data")
        #expect(Escaping.processingInstruction("a ? b") == "a ? b")
        #expect(Escaping.processingInstruction("a?>b") == "a? >b")
    }
}
