import Testing
@testable import PureXML

/// Encoding-declaration contradictions are fatal (#137, 4.3.3): a declared
/// 16/32-bit encoding over 8-bit bytes, a declaration outside the BOM's
/// family, and an external entity declaring a version above the document's
/// (errata E38).
@Suite("Encoding declaration mismatches")
struct EncodingMismatchTests {
    @Test("UTF-16 declared over 8-bit bytes is rejected")
    func test_wideOverNarrow() {
        let bytes = Array("<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n<root/>\n".utf8)
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.Parsing.ByteDecoder.decode(bytes)
        }
    }

    @Test("A declaration outside the BOM's family is rejected")
    func test_bomContradiction() {
        // UTF-8 BOM + iso-8859-1 declaration.
        let utf8: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("<?xml version='1.0' encoding='iso-8859-1'?><x/>".utf8)
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.Parsing.ByteDecoder.decode(utf8)
        }
        // UTF-16BE BOM + iso-8859-1 declaration.
        var utf16: [UInt8] = [0xFE, 0xFF]
        for scalar in "<?xml version='1.0' encoding='iso-8859-1'?><x/>".unicodeScalars {
            utf16.append(0)
            utf16.append(UInt8(scalar.value))
        }
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.Parsing.ByteDecoder.decode(utf16)
        }
        // Matching declarations stay accepted.
        let consistent: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("<?xml version='1.0' encoding='UTF-8'?><x/>".utf8)
        #expect((try? PureXML.Parsing.ByteDecoder.decode(consistent)) != nil)
    }

    @Test("An external entity declaring a higher version is rejected (E38)")
    func test_entityVersionAboveDocument() {
        let xml = "<!DOCTYPE foo [<!ELEMENT foo ANY><!ENTITY e SYSTEM \"e.ent\">]>\n<foo>&e;</foo>"
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, _ in "<?xml version=\"1.1\" encoding=\"utf-8\"?>ok" },
            resolveExternalSubset: { _ in nil },
        )
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: .init(allowDoctype: true), resolver: resolver)
        }
        let sameVersion = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, _ in "<?xml version=\"1.0\" encoding=\"utf-8\"?>ok" },
            resolveExternalSubset: { _ in nil },
        )
        #expect((try? PureXML.parse(xml, limits: .init(allowDoctype: true), resolver: sameVersion)) != nil)
    }
}
