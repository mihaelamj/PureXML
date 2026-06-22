import Testing
@testable import PureXML

/// The pull-based `StreamingDecoder` (Sources/Parsing/StreamingDecoder.swift) decodes
/// one byte at a time, so a multi-byte character is inherently assembled across pull
/// boundaries (the streaming/split path). Full-buffer decoding is covered elsewhere;
/// this gives the streaming glue (per-encoding `nextX`, BOM detection, the declared-
/// encoding override, and the malformed→replacement path) standing coverage. Expected
/// scalars were taken from the decoder itself, then pinned here.
@Suite("StreamingDecoder (byte-at-a-time decode)")
struct StreamingDecoderTests {
    /// Decodes `bytes`, pulled one at a time (so every multi-byte sequence is split).
    private func decode(_ bytes: [UInt8]) -> String {
        var index = 0
        var decoder = PureXML.Parsing.StreamingDecoder(pullingBytes: {
            defer { index += 1 }
            return index < bytes.count ? bytes[index] : nil
        })
        var out = ""
        while let character = decoder.next() {
            out.append(character)
        }
        return out
    }

    /// A CJK-declared document: an ASCII XML declaration (which decodes identically
    /// under the named encoding) followed by encoded content. `detect()` reads the
    /// `encoding=` and switches the decoder onto that path.
    private func decodeDeclared(_ encoding: String, _ content: [UInt8]) -> String {
        let prefix = Array("<?xml version='1.0' encoding='\(encoding)'?>".utf8)
        let full = decode(prefix + content)
        return String(full.dropFirst(prefix.count))
    }

    @Test("GBK: ASCII, the 0x80 euro, and a two-byte lead+trail")
    func test_gbk() {
        #expect(decodeDeclared("GBK", [0x41]) == "A")
        #expect(decodeDeclared("GBK", [0x80]) == "\u{20AC}") // euro
        #expect(decodeDeclared("GBK", [0xD6, 0xD0]) == "\u{4E2D}") // 中
        // A lead with an invalid trail yields the replacement character, not a crash.
        #expect(decodeDeclared("GBK", [0x81, 0x20]).contains("\u{FFFD}"))
    }

    @Test("the multi-byte CJK encodings each assemble across pulls")
    func test_cjkEncodings() {
        #expect(decodeDeclared("Big5", [0xA4, 0xA4]) == "\u{4E2D}") // 中
        #expect(decodeDeclared("Shift_JIS", [0x82, 0xA0]) == "\u{3042}") // あ
        #expect(decodeDeclared("EUC-KR", [0xB0, 0xA1]) == "\u{AC00}") // 가
        #expect(decodeDeclared("EUC-JP", [0xA4, 0xA2]) == "\u{3042}") // あ
        #expect(decodeDeclared("GB18030", [0x81, 0x30, 0x81, 0x30]) == "\u{0080}") // 4-byte range
    }

    @Test("BOM detection selects the UTF-16/32 path with no declaration")
    func test_bomDetection() {
        #expect(decode([0xFE, 0xFF, 0x00, 0x41]) == "A") // UTF-16BE BOM
        #expect(decode([0xFF, 0xFE, 0x41, 0x00]) == "A") // UTF-16LE BOM
        #expect(decode([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41]) == "A") // UTF-32BE BOM
        #expect(decode([0xEF, 0xBB, 0xBF, 0x41]) == "A") // UTF-8 BOM
    }

    @Test("plain UTF-8 multi-byte content decodes across pulls")
    func test_utf8MultiByte() {
        // é (U+00E9) = C3 A9, 中 (U+4E2D) = E4 B8 AD, split byte-by-byte.
        #expect(decode(Array("é中A".utf8)) == "é中A")
    }
}
