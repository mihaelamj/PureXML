@testable import PureXML
import Testing

/// Every QName a schema names (a `type`/`base`/`itemType`/`memberTypes` type, an
/// element/attribute/group/attributeGroup `ref`, an element `substitutionGroup`)
/// must resolve to a declared component or a built-in. An undeclared reference
/// was previously accepted at compile time and only surfaced (if at all) lazily
/// during instance validation. The check is skipped when the document pulls in
/// external definitions through `import`/`include`/`redefine`, which the default
/// compile does not load.
@Suite("Schema reference resolution")
struct SchemaReferenceTests {
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

    @Test("a reference to a declared component or a built-in resolves")
    func test_resolves() throws {
        try compile(#"<xs:element name="a" type="xs:string"/>"#)
        try compile(#"<xs:simpleType name="t"><xs:restriction base="xs:integer"/></xs:simpleType><xs:element name="a" type="t"/>"#)
        try compile(#"<xs:element name="g" type="xs:string"/><xs:complexType name="c"><xs:sequence><xs:element ref="g"/></xs:sequence></xs:complexType>"#)
    }

    @Test("an undeclared reference is rejected")
    func test_undeclared() {
        #expect(rejects(#"<xs:element name="a" type="DoesNotExist"/>"#))
        #expect(rejects(#"<xs:simpleType name="t"><xs:restriction base="Missing"/></xs:simpleType>"#))
        #expect(rejects(#"<xs:complexType name="c"><xs:sequence><xs:element ref="ghost"/></xs:sequence></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="c"><xs:group ref="noGroup"/></xs:complexType>"#))
    }

    @Test("a reference value tolerates surrounding whitespace (whiteSpace collapse)")
    func test_whitespacePadded() throws {
        try compile("<xs:simpleType name=\"t\"><xs:restriction base=\"  xs:string \"/></xs:simpleType>")
    }

    @Test("references are not checked when an import may supply them")
    func test_importSkipsCheck() throws {
        // A dangling reference into an imported namespace is tolerated: the default
        // compile does not load the import, so the reference cannot be verified.
        try compile(#"""
        <xs:import namespace="urn:other"/>
        <xs:element name="a" type="other:Foo" xmlns:other="urn:other"/>
        """#)
    }
}
