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
