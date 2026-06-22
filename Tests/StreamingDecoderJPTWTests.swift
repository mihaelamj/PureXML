import Testing
@testable import PureXML

/// Streaming (byte-at-a-time) coverage for the two CJK decoders the existing
/// StreamingDecoderTests did not exercise: ISO-2022-JP (mode escapes: ASCII,
/// JIS-Roman, half-width katakana, JIS X 0208) and EUC-TW (two-byte plane 1 and
/// the 0x8E four-byte plane selector). Computed scalars (ASCII, yen, overline,
/// katakana) are derived from the decoder's arithmetic; table-mapped scalars are
/// pinned from the decoder itself, matching how StreamingDecoderTests was built.
///
/// Output is compared as Unicode scalars, not Characters: a half-width katakana
/// sound mark (U+FF9F) would grapheme-cluster with the preceding declaration byte,
/// which a Character-count `dropFirst` would then swallow. The scalars are intact.
@Suite("StreamingDecoder ISO-2022-JP / EUC-TW")
struct StreamingDecoderJPTWTests {
    /// Decodes `bytes` pulled one at a time, so every multi-byte / multi-mode
    /// sequence is split across pull boundaries.
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

    /// The decoded content scalars after a declaration in `encoding`. The prefix is
    /// pure ASCII (one scalar per byte), so dropping `prefix.count` scalars leaves
    /// exactly the content's scalars.
    private func scalars(_ encoding: String, _ content: [UInt8]) -> [UInt32] {
        let prefix = Array("<?xml version='1.0' encoding='\(encoding)'?>".utf8)
        let full = decode(prefix + content)
        return Array(full.unicodeScalars.dropFirst(prefix.count)).map(\.value)
    }

    @Test("ISO-2022-JP escapes between ASCII, JIS-Roman and half-width katakana")
    func test_iso2022jpComputedModes() {
        // Default mode is ASCII.
        #expect(scalars("ISO-2022-JP", [0x41]) == [0x41])
        // ESC ( J -> JIS-Roman: 0x5C is yen, 0x7E is overline.
        #expect(scalars("ISO-2022-JP", [0x1B, 0x28, 0x4A, 0x5C]) == [0x00A5])
        #expect(scalars("ISO-2022-JP", [0x1B, 0x28, 0x4A, 0x7E]) == [0x203E])
        // ESC ( I -> half-width katakana: byte 0x21 maps to U+FF61, 0x5F to U+FF9F.
        #expect(scalars("ISO-2022-JP", [0x1B, 0x28, 0x49, 0x21]) == [0xFF61])
        #expect(scalars("ISO-2022-JP", [0x1B, 0x28, 0x49, 0x5F]) == [0xFF9F])
        // An unknown escape yields the replacement character, not a crash.
        #expect(scalars("ISO-2022-JP", [0x1B, 0x28, 0x5A]) == [0xFFFD])
    }

    @Test("ISO-2022-JP JIS X 0208 two-byte pair decodes across pulls")
    func test_iso2022jpJIS0208() {
        // ESC $ B -> JIS X 0208; ku=4,ten=2 (bytes 0x24,0x22) is あ (U+3042). An ESC ( B
        // returns to ASCII so a trailing ASCII byte decodes normally.
        #expect(scalars("ISO-2022-JP", [0x1B, 0x24, 0x42, 0x24, 0x22]) == [0x3042])
        #expect(scalars("ISO-2022-JP", [0x1B, 0x24, 0x42, 0x24, 0x22, 0x1B, 0x28, 0x42, 0x41]) == [0x3042, 0x41])
        // An invalid lead (0x20) is one replacement; its trail (0x21) is then re-read
        // as a fresh lead with no following byte, a second replacement.
        #expect(scalars("ISO-2022-JP", [0x1B, 0x24, 0x42, 0x20, 0x21]) == [0xFFFD, 0xFFFD])
    }

    @Test("EUC-TW ASCII, two-byte plane 1, and the 0x8E four-byte selector")
    func test_eucTW() {
        #expect(scalars("EUC-TW", [0x41]) == [0x41])
        // Plane-1 lead 0xA1 trail 0xA1 is the ideographic space U+3000.
        #expect(scalars("EUC-TW", [0xA1, 0xA1]) == [0x3000])
        // The 0x8E selector picks plane 1 explicitly: 0x8E 0xA1 0xA1 0xA1 is also U+3000.
        #expect(scalars("EUC-TW", [0x8E, 0xA1, 0xA1, 0xA1]) == [0x3000])
        // A lead outside 0xA1...0xFE (and not 0x8E) is the replacement character.
        #expect(scalars("EUC-TW", [0x80]) == [0xFFFD])
        #expect(scalars("EUC-TW", [0xFF]) == [0xFFFD])
    }
}
