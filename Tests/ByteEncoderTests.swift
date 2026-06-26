import Testing
@testable import PureXML

/// `PureXML.Parsing.ByteEncoder` is the public output encoder (the inverse of
/// `ByteDecoder`). It is reached through the serializer, whose tests only exercise
/// the UTF-8 default, so the transformation-format, single-byte, BOM, and naming
/// paths were untested. These assert the spec-defined byte output directly.
@Suite("ByteEncoder output encoding")
struct ByteEncoderTests {
    private typealias Encoder = PureXML.Parsing.ByteEncoder
    private typealias Encoding = PureXML.Parsing.InputEncoding

    @Test("UTF-8 encodes a BMP and a multi-byte scalar")
    func test_utf8() {
        // "A" U+0041, "€" U+20AC -> E2 82 AC.
        #expect(Encoder.encode("A€", as: .utf8) == [0x41, 0xE2, 0x82, 0xAC])
    }

    @Test("UTF-16 big- and little-endian, including an astral surrogate pair")
    func test_utf16() {
        #expect(Encoder.encode("A€", as: .utf16BigEndian) == [0x00, 0x41, 0x20, 0xAC])
        #expect(Encoder.encode("A€", as: .utf16LittleEndian) == [0x41, 0x00, 0xAC, 0x20])
        // "𐀀" U+10000 -> surrogate pair D800 DC00.
        #expect(Encoder.encode("𐀀", as: .utf16BigEndian) == [0xD8, 0x00, 0xDC, 0x00])
    }

    @Test("UTF-32 big- and little-endian")
    func test_utf32() {
        #expect(Encoder.encode("A", as: .utf32BigEndian) == [0x00, 0x00, 0x00, 0x41])
        #expect(Encoder.encode("A", as: .utf32LittleEndian) == [0x41, 0x00, 0x00, 0x00])
        #expect(Encoder.encode("𐀀", as: .utf32BigEndian) == [0x00, 0x01, 0x00, 0x00])
    }

    @Test("a single-byte encoding maps representable scalars and escapes the rest")
    func test_singleByteWithCharacterReference() {
        // "é" U+00E9 is ISO-8859-1 byte 0xE9; "€" U+20AC is not representable and
        // becomes the ASCII bytes of a decimal character reference.
        #expect(Encoder.encode("é", as: .latin1) == [0xE9])
        #expect(Encoder.encode("€", as: .latin1) == Array("&#8364;".utf8))
    }

    @Test("byte-order marks are emitted only for the UTF-16/32 forms")
    func test_byteOrderMark() {
        #expect(Encoder.byteOrderMark(.utf16BigEndian) == [0xFE, 0xFF])
        #expect(Encoder.byteOrderMark(.utf16LittleEndian) == [0xFF, 0xFE])
        #expect(Encoder.byteOrderMark(.utf32BigEndian) == [0x00, 0x00, 0xFE, 0xFF])
        #expect(Encoder.byteOrderMark(.utf32LittleEndian) == [0xFF, 0xFE, 0x00, 0x00])
        #expect(Encoder.byteOrderMark(.utf8).isEmpty)
        #expect(Encoder.byteOrderMark(.latin1).isEmpty)
    }

    @Test("supports covers the transformation formats and a single-byte family")
    func test_supports() {
        #expect(Encoder.supports(.utf8))
        #expect(Encoder.supports(.utf16BigEndian))
        #expect(Encoder.supports(.latin1))
    }

    @Test("canonical declaration names match the registered encoding labels")
    func test_canonicalName() {
        #expect(Encoder.canonicalName(.utf8) == "UTF-8")
        #expect(Encoder.canonicalName(.utf16BigEndian) == "UTF-16")
        #expect(Encoder.canonicalName(.latin1) == "ISO-8859-1")
        #expect(Encoder.canonicalName(.shiftJIS) == "Shift_JIS")
    }
}
