import Testing
@testable import PureXML

/// A complex type's effective `{attribute wildcard}` is the INTERSECTION of the
/// wildcards it draws from its own `anyAttribute` and from each referenced
/// attribute group (XSD 1.0 cos-aw-intersect): an attribute is admitted only if
/// every source admits it. Combining several `anyAttribute`s by union instead let
/// an attribute through that only one source allowed (W3C sun test007).
@Suite("Attribute wildcard intersection")
struct SchemaAttributeWildcardIntersectionTests {
    /// Two attribute groups whose namespaces do not overlap intersect to the empty
    /// wildcard, so an attribute in either single namespace is rejected.
    @Test("disjoint attribute-group wildcards admit nothing")
    func test_disjointIntersectionRejects() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:foo" xmlns="urn:foo">
          <xs:element name="emptywc"><xs:complexType>
            <xs:attributeGroup ref="ga"/>
            <xs:attributeGroup ref="gb"/>
          </xs:complexType></xs:element>
          <xs:attributeGroup name="ga"><xs:anyAttribute processContents="skip" namespace="urn:a"/></xs:attributeGroup>
          <xs:attributeGroup name="gb"><xs:anyAttribute processContents="skip" namespace="urn:b"/></xs:attributeGroup>
        </xs:schema>
        """)
        #expect(try !schema.validate(#"<emptywc xmlns="urn:foo" xmlns:a="urn:a" a:x="1"/>"#).isEmpty)
        #expect(try !schema.validate(#"<emptywc xmlns="urn:foo" xmlns:b="urn:b" b:x="1"/>"#).isEmpty)
    }

    /// A group restricted to one namespace intersected with a broader local
    /// `anyAttribute` keeps only the shared namespace: that one is admitted, the
    /// others are rejected. This is the FP-guard: the intersection must NOT reject
    /// the attribute both sources allow.
    @Test("overlapping wildcards admit the shared namespace only")
    func test_overlapKeepsSharedNamespace() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:foo" xmlns="urn:foo">
          <xs:element name="justA"><xs:complexType>
            <xs:attributeGroup ref="ga"/>
            <xs:anyAttribute processContents="skip" namespace="urn:a urn:b urn:c"/>
          </xs:complexType></xs:element>
          <xs:attributeGroup name="ga"><xs:anyAttribute processContents="skip" namespace="urn:a"/></xs:attributeGroup>
        </xs:schema>
        """)
        // urn:a is in both sources: admitted (no false positive).
        #expect(try schema.validate(#"<justA xmlns="urn:foo" xmlns:a="urn:a" a:x="1"/>"#).isEmpty)
        // urn:b is only in the local wildcard, not the group: rejected.
        #expect(try !schema.validate(#"<justA xmlns="urn:foo" xmlns:b="urn:b" b:x="1"/>"#).isEmpty)
    }

    /// A type with a SINGLE `anyAttribute` source is unchanged: intersection with no
    /// other source leaves the lone wildcard intact, so a permissive `##any` still
    /// admits everything.
    @Test("a single anyAttribute source is unaffected by intersection")
    func test_singleSourceUnchanged() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:foo" xmlns="urn:foo">
          <xs:element name="open"><xs:complexType>
            <xs:anyAttribute processContents="skip"/>
          </xs:complexType></xs:element>
        </xs:schema>
        """)
        #expect(try schema.validate(#"<open xmlns="urn:foo" xmlns:a="urn:a" a:x="1" b="2"/>"#).isEmpty)
    }
}
