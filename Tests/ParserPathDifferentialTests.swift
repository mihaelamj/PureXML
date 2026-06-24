import Testing
@testable import PureXML

/// A differential oracle for the parser's byte-level fast paths. The byte path
/// (a reader built from a `String`, which owns its UTF-8 and scans straight off
/// the bytes) and the streaming Character path (a reader built from a pulling
/// closure, whose `storage` is nil so every byte method returns nil) are two
/// implementations of the same grammar. They must therefore emit the identical
/// event stream AND, on malformed input, fail at the identical source mark, for
/// every input. Any divergence is a fast-path bug. The corpus is chosen to land
/// on the boundaries where the two paths differ in mechanism: carriage-return
/// folding, attribute-value normalization, multi-line position tracking, the
/// `]]>` guard, name limits, and the ASCII/non-ASCII handoff.
@Suite("Parser byte/Character path differential")
struct ParserPathDifferentialTests {
    private func drain(_ reader: inout PureXML.Parsing.EventReader) -> String {
        var out = ""
        do {
            while let event = try reader.next() {
                let mark = reader.eventStart
                out += "\(event)@\(mark.line):\(mark.column):\(mark.offset)|"
            }
            out += "EOF"
        } catch {
            out += "ERR:\(error)"
        }
        return out
    }

    private func bytePath(_ input: String, _ limits: PureXML.Parsing.Limits) -> String {
        var reader = PureXML.Parsing.EventReader(input, limits: limits)
        return drain(&reader)
    }

    private func characterPath(_ input: String, _ limits: PureXML.Parsing.Limits) -> String {
        var iterator = input.makeIterator()
        var reader = PureXML.Parsing.EventReader(pulling: { iterator.next() }, limits: limits)
        return drain(&reader)
    }

    private func expectAgreement(_ label: String, _ input: String, limits: PureXML.Parsing.Limits = .default) {
        let viaBytes = bytePath(input, limits)
        let viaCharacters = characterPath(input, limits)
        #expect(
            viaBytes == viaCharacters,
            "byte and Character paths diverged for \(label) on \(input.debugDescription)\n  bytes: \(viaBytes)\n  chars: \(viaCharacters)",
        )
    }

    @Test("Carriage-return and line-feed folding in content agree on both paths")
    func test_contentLineEndings() {
        expectAgreement("lone CR", "<a>x\ry</a>")
        expectAgreement("CRLF", "<a>x\r\ny</a>")
        expectAgreement("CR then CRLF", "<a>x\r\r\ny</a>")
        expectAgreement("only CR", "<a>\r</a>")
        expectAgreement("CR then element", "<a>x\r<b/></a>")
        expectAgreement("leading CRs then content and element", "<a>\r\r\rx<b/>y</a>")
        expectAgreement("multi-line then element mark", "<a>line1\nline2\nline3<b/></a>")
        expectAgreement("blank lines then element mark", "<a>\n\n\n<b/></a>")
    }

    @Test("Attribute-value normalization agrees on both paths")
    func test_attributeNormalization() {
        expectAgreement("lone CR attr", "<a v=\"x\ry\"/>")
        expectAgreement("only CR attr", "<a v=\"\r\"/>")
        expectAgreement("CR then CRLF attr", "<a v=\"x\r\r\ny\"/>")
        expectAgreement("two lone CR attr", "<a v=\"x\ry\rz\"/>")
        expectAgreement("mixed whitespace attr", "<a v=\"\t\r\n \"/>")
        expectAgreement("char-ref CR survives", "<a v=\"x&#13;y\"/>")
        expectAgreement("char-ref LF survives", "<a v=\"x&#10;y\"/>")
        expectAgreement("literal tab plus ref tab", "<a v=\"a\tb&#9;c\"/>")
        expectAgreement("multi-line attr then attr", "<a b=\"\nval\nval2\"  c=\"y\"/>")
    }

    @Test("Bracket and CDATA-close boundaries agree on both paths")
    func test_bracketBoundaries() {
        expectAgreement("trailing ]]", "<a>]]</a>")
        expectAgreement("]]> error mark", "<a>x]]>y</a>")
        expectAgreement("] then ]]>", "<a>]x]]>y</a>")
        expectAgreement("triple ] gt", "<a>]]]>x</a>")
        expectAgreement("scattered brackets", "<a>a]b]c</a>")
        expectAgreement("newline then ]]>", "<a>line1\n]]>x</a>")
        expectAgreement("leading greater-than", "<p>a > b</p>")
    }

    @Test("Name boundaries and the ASCII/non-ASCII handoff agree on both paths")
    func test_nameBoundaries() {
        let short = PureXML.Parsing.Limits(maxNameLength: 3)
        expectAgreement("over-long name", "<abcd/>", limits: short)
        expectAgreement("over-long attribute name", "<aaa bcde=\"x\"/>", limits: short)
        expectAgreement("double colon name", "<a:b:c/>")
        expectAgreement("leading colon name", "<:x/>")
        expectAgreement("non-ASCII name start", "<\u{e9}x/>")
        expectAgreement("ASCII then non-ASCII name", "<ab\u{e9}/>")
        expectAgreement("nested non-ASCII name", "<a><b\u{e9}c/></a>")
        expectAgreement("prefix then non-ASCII local", "<x:\u{e9}/>")
    }

    @Test("Error marks after multi-line byte runs agree on both paths")
    func test_errorMarksAfterRuns() {
        expectAgreement("raw less-than in attribute", "<a v=\"x<y\"/>")
        expectAgreement("invalid char in content", "<a>x\u{0}y</a>")
        expectAgreement("invalid char in attribute", "<a v=\"x\u{0}y\"/>")
        expectAgreement("invalid char after run crossing newline", "<a>hello\nworld\u{0}x</a>")
        expectAgreement("invalid char after two newlines", "<a>ab\ncd\nef\u{0}g</a>")
        expectAgreement("missing space before attribute", "<a b=\"1\"c=\"2\"/>")
        expectAgreement("missing space after newline", "<a\nb=\"1\"c=\"2\"/>")
        expectAgreement("truncated content after newline", "<a>line1\nline2<")
    }

    @Test("Entity and ampersand handling agrees on both paths")
    func test_entitiesAndAmpersands() {
        expectAgreement("ampersand-free text", "<a>just plain text</a>")
        expectAgreement("decoded entities", "<p>1 &lt; 2 &amp; ok</p>")
        expectAgreement("undefined entity mark", "<a>&unknown;</a>")
        expectAgreement("entity after run", "<a>text &amp; more &bad;</a>")
        expectAgreement("ampersand truncation after newlines", "<a>\n\nbad &x</a>")
        expectAgreement("whitespace-only content", "<a>   </a>")
        expectAgreement("tabs then element", "<a>\t\t<b/></a>")
    }
}
