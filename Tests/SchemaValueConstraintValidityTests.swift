@testable import PureXML
import Testing

/// An element/attribute `default`/`fixed` value must be a valid value of its
/// `type` (Attribute/Element Locally Valid, XSD 1.0), checked at compile time.
/// Only a built-in type is checked (a named/inline user type is left to its own
/// rules), covering the attO family (`fixed="abc"` on `xs:integer`).
@Suite("Default/fixed value validity (compile time)")
struct SchemaValueConstraintValidityTests {
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

    @Test("a built-in-typed default/fixed value outside the type's value space is rejected")
    func test_invalidValues() {
        #expect(rejects(#"<xs:attribute name="a" type="xs:integer" fixed="abc"/>"#))
        #expect(rejects(#"<xs:attribute name="a" type="xs:int" default="abc"/>"#))
        #expect(rejects(#"<xs:element name="e" type="xs:int" default="1 2"/>"#))
        #expect(rejects(#"<xs:element name="e" type="xs:boolean" fixed="maybe"/>"#))
        #expect(rejects(#"<xs:attribute name="a" type="xs:date" default="not-a-date"/>"#))
    }

    @Test("a valid built-in-typed default/fixed value compiles, with whitespace normalized")
    func test_validValues() throws {
        try compile(#"<xs:attribute name="a" type="xs:integer" fixed="42"/>"#)
        try compile(#"<xs:element name="e" type="xs:int" default=" 5 "/>"#)
        try compile(#"<xs:attribute name="a" type="xs:boolean" default="true"/>"#)
        try compile(#"<xs:element name="e" type="xs:string" fixed="anything goes"/>"#)
    }

    @Test("a default/fixed value on a non-built-in type is left alone")
    func test_userTypeUnchecked() throws {
        try compile(#"""
        <xs:simpleType name="t"><xs:restriction base="xs:string"/></xs:simpleType>
        <xs:attribute name="a" type="t" fixed="anything"/>
        """#)
    }
}
