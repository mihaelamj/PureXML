@testable import PureXML
import Testing

/// An element may carry at most one attribute whose type is `xs:ID` (XSD 1.0
/// §3.4.6, cvc-complex-type). Two ID-typed attributes on one element, whether
/// declared or admitted through an attribute wildcard, are invalid; one is fine.
@Suite("at most one ID attribute per element")
struct SchemaTwoIDAttributesTests {
    /// The W3C attZ014 shape: the two ID-typed attributes are not declared on the
    /// type (which would already be a schema error) but enter the instance through
    /// an `anyAttribute` wildcard that admits two ID-typed global attributes, one
    /// of them a restriction of `xs:ID`.
    @Test("two ID-typed attributes admitted via a wildcard are rejected")
    func test_twoWildcardIDsRejected() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="idSub"><xs:restriction base="xs:ID"/></xs:simpleType>
          <xs:attribute name="a" type="xs:ID"/>
          <xs:attribute name="b" type="idSub"/>
          <xs:element name="e"><xs:complexType><xs:anyAttribute processContents="strict"/></xs:complexType></xs:element>
        </xs:schema>
        """)
        #expect(try !schema.validate(#"<e a="i1" b="i2"/>"#).isEmpty)
    }

    @Test("a single ID attribute plus non-ID attributes is accepted")
    func test_singleIDAccepted() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="e"><xs:complexType>
            <xs:attribute name="id" type="xs:ID"/>
            <xs:attribute name="ref" type="xs:IDREF"/>
            <xs:attribute name="s" type="xs:string"/>
          </xs:complexType></xs:element>
        </xs:schema>
        """)
        #expect(try schema.validate(#"<e id="i1" ref="i1" s="x"/>"#).isEmpty)
    }
}
