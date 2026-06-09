@testable import PureXML
import Testing

@Suite("Output encoding")
struct OutputEncodingTests {
    private func rootText(_ node: PureXML.Model.Node) -> String? {
        guard case let .document(children) = node else { return nil }
        for child in children {
            if case let .element(element) = child { return element.text }
        }
        return nil
    }

    private func serialized(_ xml: String, _ encoding: PureXML.Parsing.InputEncoding) throws -> [UInt8] {
        try PureXML.serialize(PureXML.parse(xml), encoding: encoding)
    }

    @Test("ISO-8859-1 emits one byte per Latin-1 scalar and round-trips")
    func test_latin1() throws {
        let bytes = try serialized("<r>caf\u{E9}</r>", .latin1) // café
        #expect(bytes.contains(0xE9)) // é is a single 0xE9 byte
        #expect(!bytes.contains(0xC3)) // not the UTF-8 lead byte of é
        try #expect(rootText(PureXML.parse(bytes: bytes)) == "caf\u{E9}")
    }

    @Test("ISO-8859-7 round-trips Greek and windows-1252 round-trips its punctuation")
    func test_greekAndWindows() throws {
        try #expect(rootText(PureXML.parse(bytes: serialized("<r>\u{0391}</r>", .greek))) == "\u{0391}") // Α
        try #expect(rootText(PureXML.parse(bytes: serialized("<r>\u{20AC}\u{201C}</r>", .windows1252))) == "\u{20AC}\u{201C}")
    }

    @Test("An unrepresentable scalar becomes a numeric character reference")
    func test_characterReferenceFallback() throws {
        // U+4E2D (中) is not in Latin-1, so it is written as &#20013; (decimal).
        let bytes = try serialized("<r>\u{4E2D}</r>", .latin1)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains("&#20013;"))
        // The reference bytes are ASCII, so they re-parse to the original scalar.
        try #expect(rootText(PureXML.parse(bytes: bytes)) == "\u{4E2D}")
    }

    @Test("The declaration carries the canonical encoding name")
    func test_declarationName() throws {
        let text = try String(decoding: serialized("<r>x</r>", .latin1), as: UTF8.self)
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>"))
    }

    @Test("UTF-16 output carries a byte-order mark and round-trips")
    func test_utf16() throws {
        let bytes = try serialized("<r>hi\u{4E2D}</r>", .utf16BigEndian)
        #expect(Array(bytes.prefix(2)) == [0xFE, 0xFF]) // BOM
        try #expect(rootText(PureXML.parse(bytes: bytes)) == "hi\u{4E2D}")
    }

    /// Encodes the content, asserts it was truly encoded (no character-reference
    /// fallback), then re-parses it back to the original text.
    private func roundTrip(_ content: String, _ encoding: PureXML.Parsing.InputEncoding) throws {
        let bytes = try serialized("<r>\(content)</r>", encoding)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("&#"))
        try #expect(rootText(PureXML.parse(bytes: bytes)) == content)
    }

    @Test("Shift-JIS and EUC-JP round-trip Japanese")
    func test_japanese() throws {
        try roundTrip("\u{65E5}\u{672C}\u{FF71}", .shiftJIS) // 日本 + half-width katakana ｱ
        try roundTrip("\u{65E5}\u{672C}", .eucJP)
    }

    @Test("EUC-KR round-trips Hangul")
    func test_korean() throws {
        try roundTrip("\u{AC00}\u{D55C}", .eucKR) // 가한
    }

    @Test("GBK and Big5 round-trip Chinese")
    func test_chinese() throws {
        try roundTrip("\u{4E2D}\u{6587}", .gbk) // 中文
        try roundTrip("\u{4E2D}\u{6587}", .big5)
    }

    @Test("GB18030 round-trips a two-byte BMP char and a four-byte astral char")
    func test_gb18030() throws {
        try roundTrip("\u{4E2D}", .gb18030) // 中, two-byte
        try roundTrip("\u{20000}", .gb18030) // 𠀀, four-byte astral
        // The astral char must use the four-byte form, not a character reference.
        let bytes = try serialized("<r>\u{20000}</r>", .gb18030)
        try #expect(rootText(PureXML.parse(bytes: bytes)) == "\u{20000}")
    }
}
