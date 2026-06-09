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
}
