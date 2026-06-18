import Testing
@testable import PureXML

/// The ur-type `xsd:anyType` processes its element and attribute wildcards as
/// `lax`, not `skip` (XSD 1.0 §3.4.7). A child or attribute of an untyped element
/// that has a global declaration is validated against it; undeclared content is
/// admitted. Lax lookup matches a global declaration only by full qualified name,
/// so an unqualified instance element is never conflated with a namespaced global
/// of the same local name.
@Suite("anyType lax wildcard processing")
struct SchemaAnyTypeLaxTests {
    /// No target namespace: the untyped `data` element laxly validates its `item`
    /// child, whose `anyAttribute` (strict by default) in turn validates the
    /// duration-typed attribute. "P" is not a valid duration, so it is rejected;
    /// a well-formed duration passes; an undeclared child is admitted (lax skips).
    private func noNamespaceSchema() throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <xsd:attribute name="DUR" type="xsd:duration"/>
          <xsd:element name="data"/>
          <xsd:element name="item"><xsd:complexType><xsd:anyAttribute/></xsd:complexType></xsd:element>
        </xsd:schema>
        """)
    }

    @Test("a declared child under an untyped element is laxly validated")
    func test_declaredChildValidated() throws {
        let schema = try noNamespaceSchema()
        #expect(try !schema.validate(#"<data><item DUR="P"/></data>"#).isEmpty)
        #expect(try schema.validate(#"<data><item DUR="P1Y"/></data>"#).isEmpty)
    }

    @Test("an undeclared child under an untyped element is admitted")
    func test_undeclaredChildAdmitted() throws {
        let schema = try noNamespaceSchema()
        #expect(try schema.validate(#"<data><nope>anything</nope></data>"#).isEmpty)
    }

    /// An unqualified instance element must not match a namespaced global of the
    /// same local name. Here `testContent` (type `xs:short`) is in the target
    /// namespace; an unqualified `<testContent>any text</testContent>` under an
    /// untyped element is undeclared in no-namespace, so lax processing skips it
    /// rather than validating "any text" as `xs:short`.
    @Test("lax lookup does not conflate an unqualified child with a namespaced global")
    func test_noNamespaceConflation() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema targetNamespace="urn:t" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:t="urn:t">
          <xs:element name="root"><xs:complexType><xs:sequence>
            <xs:element name="hole" type="xs:anyType"/>
          </xs:sequence></xs:complexType></xs:element>
          <xs:element name="testContent" type="xs:short"/>
        </xs:schema>
        """)
        // Unqualified `testContent` is undeclared in no-namespace: admitted (lax skip).
        #expect(try schema.validate(#"<t:root xmlns:t="urn:t"><hole><testContent>any text</testContent></hole></t:root>"#).isEmpty)
        // The namespaced `testContent` IS declared `xs:short`: a non-short value is rejected.
        #expect(try !schema.validate(#"<t:root xmlns:t="urn:t"><hole><t:testContent>any text</t:testContent></hole></t:root>"#).isEmpty)
        // A valid short under the namespaced declaration passes.
        #expect(try schema.validate(#"<t:root xmlns:t="urn:t"><hole><t:testContent>123</t:testContent></hole></t:root>"#).isEmpty)
    }
}
