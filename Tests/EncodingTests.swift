@testable import PureXML
import Testing

@Suite("Encoding")
struct EncodingTests {
    @Test("Detects encodings from the leading bytes")
    func test_detect() {
        let detect = PureXML.Parsing.InputEncoding.detect
        #expect(detect([0xEF, 0xBB, 0xBF, 0x3C]) == .utf8)
        #expect(detect([0xFE, 0xFF, 0x00, 0x3C]) == .utf16BigEndian)
        #expect(detect([0xFF, 0xFE, 0x3C, 0x00]) == .utf16LittleEndian)
        #expect(detect([0x00, 0x3C, 0x00, 0x3F]) == .utf16BigEndian)
        #expect(detect([0x3C, 0x00, 0x3F, 0x00]) == .utf16LittleEndian)
        #expect(detect(Array("<r/>".utf8)) == .utf8)
    }

    @Test("Parses UTF-8 bytes, with and without a BOM")
    func test_parseUTF8Bytes() throws {
        let plain = try PureXML.parse(bytes: Array("<r>hi</r>".utf8))
        #expect(rootText(plain) == "hi")
        let withBOM = try PureXML.parse(bytes: [0xEF, 0xBB, 0xBF] + Array("<r>hi</r>".utf8))
        #expect(rootText(withBOM) == "hi")
    }

    @Test("Parses UTF-16 bytes in both byte orders")
    func test_parseUTF16Bytes() throws {
        let bigEndianNode = try PureXML.parse(bytes: utf16("<r>hi</r>", bigEndian: true))
        #expect(rootText(bigEndianNode) == "hi")
        let littleEndianNode = try PureXML.parse(bytes: utf16("<r>hi</r>", bigEndian: false))
        #expect(rootText(littleEndianNode) == "hi")
    }

    @Test("Decodes a UTF-8 byte stream incrementally (multi-byte scalars)")
    func test_streamingUTF8() throws {
        let node = try PureXML.parse(pullingBytes: byteSource(Array("<r>café \u{1F600}</r>".utf8)))
        #expect(rootText(node) == "café \u{1F600}")
    }

    @Test("Decodes a UTF-16 byte stream incrementally, both byte orders")
    func test_streamingUTF16() throws {
        let bigEndianNode = try PureXML.parse(pullingBytes: byteSource(utf16("<r>héllo</r>", bigEndian: true)))
        #expect(rootText(bigEndianNode) == "héllo")
        let littleEndianNode = try PureXML.parse(pullingBytes: byteSource(utf16("<r>héllo</r>", bigEndian: false)))
        #expect(rootText(littleEndianNode) == "héllo")
    }

    @Test("Odd-length UTF-16 input is rejected as malformed")
    func test_malformedUTF16() {
        #expect(throws: PureXML.Parsing.ParseError.malformedEncoding) {
            _ = try PureXML.parse(bytes: [0xFE, 0xFF, 0x00])
        }
    }

    @Test("Detects UTF-32 byte-order marks")
    func test_detectUTF32() {
        #expect(PureXML.Parsing.InputEncoding.detect([0x00, 0x00, 0xFE, 0xFF, 0x00]) == .utf32BigEndian)
        #expect(PureXML.Parsing.InputEncoding.detect([0xFF, 0xFE, 0x00, 0x00, 0x00]) == .utf32LittleEndian)
    }

    @Test("Parses UTF-32 bytes in both byte orders")
    func test_parseUTF32() throws {
        try #expect(rootText(PureXML.parse(bytes: utf32("<r>hi</r>", bigEndian: true))) == "hi")
        try #expect(rootText(PureXML.parse(bytes: utf32("<r>hi</r>", bigEndian: false))) == "hi")
    }

    @Test("Honors a declared ISO-8859-1 encoding")
    func test_latin1() throws {
        var bytes = Array("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><r>caf".utf8)
        bytes.append(0xE9) // small letter e with acute, in Latin-1
        bytes += Array("</r>".utf8)
        try #expect(rootText(PureXML.parse(bytes: bytes)) == "caf\u{E9}")
    }

    @Test("Honors a declared Windows-1252 encoding")
    func test_windows1252() throws {
        var bytes = Array("<?xml version=\"1.0\" encoding=\"windows-1252\"?><r>".utf8)
        bytes.append(0x80) // euro sign in CP1252
        bytes += Array("</r>".utf8)
        try #expect(rootText(PureXML.parse(bytes: bytes)) == "\u{20AC}")
    }

    private func decoded(_ encoding: String, _ high: [UInt8]) throws -> String? {
        var bytes = Array("<?xml version=\"1.0\" encoding=\"\(encoding)\"?><r>".utf8)
        bytes += high
        bytes += Array("</r>".utf8)
        return try rootText(PureXML.parse(bytes: bytes))
    }

    @Test("Decodes ISO-8859-15: euro and the Latin-9 substitutions")
    func test_iso8859_15() throws {
        try #expect(decoded("ISO-8859-15", [0xA4]) == "\u{20AC}") // €
        try #expect(decoded("ISO-8859-15", [0xBD]) == "\u{0153}") // œ
        try #expect(decoded("ISO-8859-15", [0xE9]) == "\u{E9}") // é, unchanged from Latin-1
    }

    @Test("Decodes ISO-8859-9: the Turkish letters")
    func test_iso8859_9() throws {
        try #expect(decoded("ISO-8859-9", [0xDD]) == "\u{0130}") // İ
        try #expect(decoded("ISO-8859-9", [0xFE]) == "\u{015F}") // ş
        try #expect(decoded("ISO-8859-9", [0xE9]) == "\u{E9}") // é, unchanged from Latin-1
    }

    @Test("Decodes ISO-8859-2 (Latin-2) from the vendored table")
    func test_iso8859_2() throws {
        try #expect(decoded("ISO-8859-2", [0xA1]) == "\u{0104}") // Ą
        try #expect(decoded("ISO-8859-2", [0xE8]) == "\u{010D}") // č
        try #expect(decoded("ISO-8859-2", [0xE9]) == "\u{E9}") // é
        try #expect(decoded("ISO-8859-2", [0xFF]) == "\u{02D9}") // ˙
    }

    @Test("Decodes the vendored ISO-8859 Latin and Greek tables")
    func test_vendoredTables() throws {
        try #expect(decoded("ISO-8859-3", [0xA1]) == "\u{0126}") // Ħ
        try #expect(decoded("ISO-8859-3", [0xC6]) == "\u{0108}") // Ĉ
        try #expect(decoded("ISO-8859-4", [0xA1]) == "\u{0104}") // Ą
        try #expect(decoded("ISO-8859-4", [0xC0]) == "\u{0100}") // Ā
        try #expect(decoded("ISO-8859-7", [0xC1]) == "\u{0391}") // Α
        try #expect(decoded("ISO-8859-7", [0xE1]) == "\u{03B1}") // α
        try #expect(decoded("ISO-8859-7", [0xA4]) == "\u{20AC}") // €
        try #expect(decoded("ISO-8859-13", [0xA8]) == "\u{00D8}") // Ø
        try #expect(decoded("ISO-8859-13", [0xC0]) == "\u{0104}") // Ą
        try #expect(decoded("ISO-8859-6", [0xC7]) == "\u{0627}") // ا (Arabic alef)
        try #expect(decoded("ISO-8859-8", [0xE0]) == "\u{05D0}") // א (Hebrew alef)
        try #expect(decoded("ISO-8859-10", [0xFF]) == "\u{0138}") // ĸ
        try #expect(decoded("ISO-8859-14", [0xA1]) == "\u{1E02}") // Ḃ
        try #expect(decoded("ISO-8859-16", [0xAA]) == "\u{0218}") // Ș
    }

    @Test("Decodes ISO-8859-5: the Cyrillic block")
    func test_iso8859_5() throws {
        try #expect(decoded("ISO-8859-5", [0xB0]) == "\u{0410}") // А
        try #expect(decoded("ISO-8859-5", [0xE0]) == "\u{0440}") // р
        try #expect(decoded("ISO-8859-5", [0xF0]) == "\u{2116}") // №
    }

    @Test("Decodes Windows-1254: CP1252 punctuation plus the Turkish letters")
    func test_windows1254() throws {
        try #expect(decoded("windows-1254", [0x80]) == "\u{20AC}") // € (from CP1252 high range)
        try #expect(decoded("windows-1254", [0xDE]) == "\u{015E}") // Ş
        try #expect(decoded("windows-1254", [0xE9]) == "\u{E9}") // é, unchanged
    }

    private func byteSource(_ bytes: [UInt8]) -> () -> UInt8? {
        var index = 0
        return {
            guard index < bytes.count else { return nil }
            defer { index += 1 }
            return bytes[index]
        }
    }

    private func utf16(_ string: String, bigEndian: Bool) -> [UInt8] {
        var bytes: [UInt8] = bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]
        for unit in string.utf16 {
            let high = UInt8(unit >> 8)
            let low = UInt8(unit & 0xFF)
            bytes += bigEndian ? [high, low] : [low, high]
        }
        return bytes
    }

    private func utf32(_ string: String, bigEndian: Bool) -> [UInt8] {
        var bytes: [UInt8] = bigEndian ? [0x00, 0x00, 0xFE, 0xFF] : [0xFF, 0xFE, 0x00, 0x00]
        for scalar in string.unicodeScalars {
            let value = scalar.value
            let bigEndianBytes = [
                UInt8(value >> 24 & 0xFF),
                UInt8(value >> 16 & 0xFF),
                UInt8(value >> 8 & 0xFF),
                UInt8(value & 0xFF),
            ]
            bytes += bigEndian ? bigEndianBytes : bigEndianBytes.reversed()
        }
        return bytes
    }

    private func rootText(_ node: PureXML.Model.Node) -> String? {
        guard case let .document(children) = node else { return nil }
        for child in children {
            if case let .element(element) = child { return element.text }
        }
        return nil
    }
}
