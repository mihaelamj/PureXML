import Testing
@testable import PureXML

/// A `simpleContent` derivation whose base is another complex type with
/// simpleContent resolves through the chain to the underlying simple type, so the
/// element's text is validated against it. A type restricting (or extending) a
/// complex type that ultimately derives from `xs:int` validates its content as an
/// int, not as unconstrained string (W3C sun baseTD00101).
@Suite("simpleContent base chain")
struct SchemaSimpleContentChainTests {
    private func schema(method: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xsd:schema xmlns="u" xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="u">
          <xsd:element name="root" type="Test"/>
          <xsd:complexType name="Test"><xsd:simpleContent>
            <xsd:\(method) base="Test2"/>
          </xsd:simpleContent></xsd:complexType>
          <xsd:complexType name="Test2"><xsd:simpleContent>
            <xsd:extension base="xsd:int"/>
          </xsd:simpleContent></xsd:complexType>
        </xsd:schema>
        """)
    }

    @Test("text invalid for the chained int base is rejected, valid int accepted")
    func test_restrictionChainValidatesAsInt() throws {
        let restriction = try schema(method: "restriction")
        #expect(try !restriction.validate(#"<root xmlns="u">b</root>"#).isEmpty)
        #expect(try restriction.validate(#"<root xmlns="u">42</root>"#).isEmpty)
    }

    @Test("an extension chain to int also validates the content as int")
    func test_extensionChainValidatesAsInt() throws {
        let extension0 = try schema(method: "extension")
        #expect(try !extension0.validate(#"<root xmlns="u">b</root>"#).isEmpty)
        #expect(try extension0.validate(#"<root xmlns="u">42</root>"#).isEmpty)
    }
}
