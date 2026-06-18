import Testing
@testable import PureXML

/// Value-space validity of the `final`/`block` derivation-control attributes
/// (XSD 1.0): `#all` or a whitespace list of method tokens, with the admitted
/// tokens depending on the component (element/complexType/simpleType) and on
/// whether it is `final` or `block`. The elemF / st_final families.
@Suite("Derivation control (final/block) value space")
struct SchemaDerivationControlTests {
    private func rejects(_ body: String) -> Bool {
        do {
            _ = try PureXML.Schema.Document("""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            \(body)
            </xs:schema>
            """)
            return false
        } catch {
            return true
        }
    }

    @Test("element final admits only extension/restriction; block also substitution")
    func test_element() {
        // substitution is a block token, not a final token.
        #expect(rejects(#"<xs:element name="e" type="xs:string" final="substitution"/>"#))
        #expect(rejects(#"<xs:element name="e" type="xs:string" final="extension restriction substitution"/>"#))
        // unknown token and wrong case.
        #expect(rejects(#"<xs:element name="e" type="xs:string" final="foo"/>"#))
        #expect(rejects(##"<xs:element name="e" type="xs:string" final="#All"/>"##))
        #expect(rejects(#"<xs:element name="e" type="xs:string" final="Extension"/>"#))
        // valid finals and a valid block with substitution.
        #expect(!rejects(##"<xs:element name="e" type="xs:string" final="#all"/>"##))
        #expect(!rejects(#"<xs:element name="e" type="xs:string" final="extension restriction"/>"#))
        #expect(!rejects(#"<xs:element name="e" type="xs:string" block="substitution"/>"#))
    }

    @Test("simpleType final admits list/union/restriction, not extension")
    func test_simpleType() {
        #expect(rejects(#"<xs:simpleType name="t" final="extension"><xs:restriction base="xs:string"/></xs:simpleType>"#))
        #expect(!rejects(#"<xs:simpleType name="t" final="list union restriction"><xs:restriction base="xs:string"/></xs:simpleType>"#))
        #expect(!rejects(##"<xs:simpleType name="t" final="#all"><xs:restriction base="xs:string"/></xs:simpleType>"##))
    }

    @Test("complexType block/final admit only extension/restriction")
    func test_complexType() {
        #expect(rejects(#"<xs:complexType name="t" block="substitution"><xs:sequence/></xs:complexType>"#))
        #expect(!rejects(#"<xs:complexType name="t" final="restriction"><xs:sequence/></xs:complexType>"#))
    }
}
