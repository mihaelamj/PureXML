import Testing
@testable import PureXML

@Suite("HTML tokenizer: references, NUL, RCDATA")
struct HTMLTokenizerTests {
    /// The concatenated text content of the first parsed element.
    private func text(_ html: String) -> String {
        guard case let .document(children) = PureXML.HTML.parse(html), case let .element(element) = children.first else { return "" }
        return element.children.compactMap { if case let .text(value) = $0 { value } else { nil } }.joined()
    }

    @Test("A numeric reference to zero, a surrogate, or an out-of-range value yields U+FFFD")
    func test_numericInvalid() {
        #expect(text("<p>&#0;</p>") == "\u{FFFD}")
        #expect(text("<p>&#xD800;</p>") == "\u{FFFD}")
        #expect(text("<p>&#x110000;</p>") == "\u{FFFD}")
    }

    @Test("A numeric reference in the C1 range is mapped to its Windows-1252 character")
    func test_numericC1() {
        #expect(text("<p>&#x80;</p>") == "\u{20AC}") // euro
        #expect(text("<p>&#153;</p>") == "\u{2122}") // trade mark
    }

    @Test("A valid numeric reference resolves to its code point")
    func test_numericValid() {
        #expect(text("<p>&#65;&#x42;</p>") == "AB")
    }

    @Test("A literal NUL byte becomes U+FFFD")
    func test_nullReplacement() {
        #expect(text("<p>a\u{0}b</p>") == "a\u{FFFD}b")
    }

    @Test("A named reference without a trailing semicolon is still decoded")
    func test_semicolonless() {
        #expect(text("<p>&amp</p>") == "&")
        #expect(text("<p>&copy</p>") == "\u{A9}")
    }

    @Test("RCDATA content (title, textarea) decodes references; raw text (style) does not")
    func test_rcdataDecoding() {
        #expect(text("<title>a &amp; b</title>") == "a & b")
        #expect(text("<textarea>&lt;x&gt;</textarea>") == "<x>")
        #expect(text("<style>a &amp; b</style>") == "a &amp; b")
    }

    @Test("A single leading newline after <textarea> is stripped")
    func test_textareaLeadingNewline() {
        #expect(text("<textarea>\nhello</textarea>") == "hello")
        #expect(text("<textarea>\n\nhello</textarea>") == "\nhello")
    }

    @Test("The HTML4 named entity set decodes across its categories")
    func test_namedEntitySet() {
        #expect(text("<p>&frac12;&Aacute;&times;</p>") == "\u{BD}\u{C1}\u{D7}") // Latin-1
        #expect(text("<p>&OElig;&dagger;&mdash;</p>") == "\u{152}\u{2020}\u{2014}") // special
        #expect(text("<p>&alpha;&Omega;&pi;</p>") == "\u{3B1}\u{3A9}\u{3C0}") // Greek
        #expect(text("<p>&forall;&sum;&infin;&ne;</p>") == "\u{2200}\u{2211}\u{221E}\u{2260}") // math
        #expect(text("<p>&larr;&rarr;&hArr;</p>") == "\u{2190}\u{2192}\u{21D4}") // arrows
        #expect(text("<p>&hearts;&diams;&spades;</p>") == "\u{2665}\u{2666}\u{2660}") // suits
        #expect(text("<p>&copy &reg</p>") == "\u{A9} \u{AE}") // semicolon-less
    }

    @Test("The full WHATWG reference set decodes astral and multi-codepoint names")
    func test_fullEntitySet() {
        #expect(PureXML.HTML.Tokenizer.namedEntities.count == 2125)
        #expect(text("<p>&fopf;</p>") == "\u{1D557}") // astral double-struck f
        #expect(text("<p>&NotEqualTilde;</p>") == "\u{2242}\u{0338}") // two codepoints
        #expect(text("<p>&CounterClockwiseContourIntegral;</p>") == "\u{2233}") // 31-char name
    }
}
