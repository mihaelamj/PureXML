import Testing
@testable import PureXML

/// `Escaping.text` and `Escaping.attribute` copy the verbatim runs between
/// escapable characters in bulk instead of appending each character one at a
/// time. These pin the escaped output against the per-character reference for
/// markers at the start, end, and adjacent; long verbatim runs around them;
/// multibyte runs (the copied run spans whole graphemes); both quote styles;
/// and ASCII-only mode (where a non-ASCII character escapes and an ASCII one is
/// copied with its run).
@Suite("Escaping bulk-copy equivalence")
struct EscapingBulkCopyTests {
    private typealias Escaping = PureXML.Emitting.Escaping

    /// The per-character escaping the bulk path replaced, kept here as the oracle.
    private func referenceText(_ value: String, asciiOnly: Bool, escapeCarriageReturn: Bool) -> String {
        var result = ""
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\r" where escapeCarriageReturn: result += "&#xD;"
            default:
                if asciiOnly {
                    for scalar in character.unicodeScalars {
                        result += scalar.value > 0x7F ? "&#x\(String(scalar.value, radix: 16, uppercase: true));" : String(scalar)
                    }
                } else {
                    result += String(character)
                }
            }
        }
        return result
    }

    private static let texts = [
        "plain text no markup",
        "a & b < c > d",
        "&<>", "&start", "end&", "&&&",
        "café & thé", "e\u{0301} < x", "\u{1F600}&\u{1F601}",
        "tab\tnewline\ncr\r", "naïve résumé",
        String(repeating: "x", count: 300) + "&" + String(repeating: "y", count: 300),
    ]

    @Test("text bulk-escape matches the per-character reference")
    func test_textEquivalence() {
        for value in Self.texts {
            for asciiOnly in [false, true] {
                for escapeCR in [false, true] {
                    #expect(
                        Escaping.text(value, asciiOnly: asciiOnly, escapeCarriageReturn: escapeCR)
                            == referenceText(value, asciiOnly: asciiOnly, escapeCarriageReturn: escapeCR),
                        "text mismatch for \(value.debugDescription) ascii=\(asciiOnly) cr=\(escapeCR)",
                    )
                }
            }
        }
    }

    @Test("attribute bulk-escape escapes quotes, markup, and whitespace")
    func test_attributeEquivalence() {
        #expect(Escaping.attribute(#"a "b" c"#, quote: "\"") == "a &quot;b&quot; c")
        #expect(Escaping.attribute("a 'b' c", quote: "'") == "a &apos;b&apos; c")
        #expect(Escaping.attribute(#"a "b" 'c'"#, quote: "\"") == #"a &quot;b&quot; 'c'"#)
        #expect(Escaping.attribute("x & y < z", quote: "\"") == "x &amp; y &lt; z")
        #expect(Escaping.attribute("tab\tnl\ncr\r", quote: "\"") == "tab&#9;nl&#10;cr&#13;")
        #expect(Escaping.attribute("café & \"q\"", quote: "\"") == "café &amp; &quot;q&quot;")
        #expect(Escaping.attribute("no escapes here", quote: "\"") == "no escapes here")
    }

    @Test("a document with re-escaped content round-trips identically")
    func test_documentRoundTrip() throws {
        let document = #"<r a="x &amp; &quot;y&quot;">t &amp; u &lt; v</r>"#
        let tree = try PureXML.parseTree(document)
        let again = try PureXML.parseTree(PureXML.serialize(tree.node))
        #expect(PureXML.serialize(tree.node) == PureXML.serialize(again.node))
    }
}
