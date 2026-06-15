@testable import PureXML
import Testing

/// Component-name uniqueness (XSD 1.0 symbol-space constraints): within a schema,
/// global type names (simpleType and complexType share one space), global element
/// names, global attribute names, named model-group names, and named
/// attribute-group names must each be unique, and identity-constraint names must
/// be unique across the document. A duplicate was previously accepted, with the
/// later definition silently overwriting the earlier one.
@Suite("Schema component-name uniqueness")
struct SchemaNameUniquenessTests {
    private func compile(_ body: String) throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        \(body)
        </xs:schema>
        """)
    }

    private func rejects(_ body: String) -> Bool {
        do { try compile(body)
            return false
        } catch { return true }
    }

    @Test("distinct global names compile")
    func test_valid() throws {
        try compile(#"""
        <xs:simpleType name="t"><xs:restriction base="xs:string"/></xs:simpleType>
        <xs:complexType name="c"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:complexType>
        <xs:element name="e" type="t"/>
        """#)
        // A name shared across different symbol spaces (a type and an element) is
        // allowed.
        try compile(#"""
        <xs:element name="x" type="xs:string"/>
        <xs:complexType name="x"><xs:sequence/></xs:complexType>
        """#)
    }

    @Test("a duplicate global type name is rejected (one symbol space)")
    func test_duplicateType() {
        #expect(rejects(#"<xs:simpleType name="t"><xs:restriction base="xs:string"/></xs:simpleType><xs:simpleType name="t"><xs:restriction base="xs:int"/></xs:simpleType>"#))
        // simpleType and complexType share the type symbol space.
        #expect(rejects(#"<xs:simpleType name="t"><xs:restriction base="xs:string"/></xs:simpleType><xs:complexType name="t"><xs:sequence/></xs:complexType>"#))
    }

    @Test("a duplicate global element or attribute name is rejected")
    func test_duplicateElementAttribute() {
        #expect(rejects(#"<xs:element name="e" type="xs:string"/><xs:element name="e" type="xs:int"/>"#))
        #expect(rejects(#"<xs:attribute name="a" type="xs:string"/><xs:attribute name="a" type="xs:int"/>"#))
    }

    @Test("a keyref refer must name a key or unique")
    func test_keyrefRefer() throws {
        // refer to a defined key resolves.
        try compile(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="@id"/></xs:key>
          <xs:keyref name="r" refer="k"><xs:selector xpath="a"/><xs:field xpath="@ref"/></xs:keyref>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="id" type="xs:string"/><xs:attribute name="ref" type="xs:string"/></xs:complexType></xs:element>
        """#)
        // refer to a name that is not a key/unique is rejected.
        #expect(rejects(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:keyref name="r" refer="ghost"><xs:selector xpath="a"/><xs:field xpath="@ref"/></xs:keyref>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="ref" type="xs:string"/></xs:complexType></xs:element>
        """#))
    }

    @Test("a keyref arity must match its referenced key or unique")
    func test_keyrefArityMismatch() {
        // keyref and key have different arities (1 vs 2): must be rejected.
        #expect(rejects(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:key name="k">
            <xs:selector xpath="a"/>
            <xs:field xpath="@id1"/>
            <xs:field xpath="@id2"/>
          </xs:key>
          <xs:keyref name="r" refer="k">
            <xs:selector xpath="a"/>
            <xs:field xpath="@ref"/>
          </xs:keyref>
        </xs:element>
        <xs:element name="a">
          <xs:complexType>
            <xs:attribute name="id1" type="xs:string"/>
            <xs:attribute name="id2" type="xs:string"/>
            <xs:attribute name="ref" type="xs:string"/>
          </xs:complexType>
        </xs:element>
        """#))
    }

    @Test("a duplicate identity-constraint name is rejected")
    func test_duplicateIdentityConstraint() {
        #expect(rejects(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:unique name="dup"><xs:selector xpath="a"/><xs:field xpath="@id"/></xs:unique>
          <xs:unique name="dup"><xs:selector xpath="a"/><xs:field xpath="@k"/></xs:unique>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="id" type="xs:string"/><xs:attribute name="k" type="xs:string"/></xs:complexType></xs:element>
        """#))
    }
}
