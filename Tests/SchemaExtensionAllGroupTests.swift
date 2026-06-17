@testable import PureXML
import Testing

@Suite("XSD all-group in extension (cos-all-limited.1.2 via extension)")
struct SchemaExtensionAllGroupTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    private func ext(base: String, content: String) -> String {
        "<xs:complexType name=\"fooType\"><xs:complexContent>"
            + "<xs:extension base=\"\(base)\">\(content)</xs:extension>"
            + "</xs:complexContent></xs:complexType>"
    }

    private let seqBase = "<xs:complexType name=\"myType\"><xs:sequence>"
        + "<xs:element name=\"a\" type=\"xs:string\"/></xs:sequence></xs:complexType>"
    private let emptyBase = "<xs:complexType name=\"emptyType\"><xs:attribute name=\"x\" type=\"xs:string\"/></xs:complexType>"
    private let allContent = "<xs:all><xs:element name=\"b\" type=\"xs:string\"/></xs:all>"

    @Test("An all group extending a base with content is rejected")
    func test_allExtendingContentRejected() {
        #expect(!compiles(seqBase + ext(base: "myType", content: allContent)))
    }

    @Test("An all group extending an empty base compiles")
    func test_allExtendingEmptyAccepted() {
        #expect(compiles(emptyBase + ext(base: "emptyType", content: allContent)))
    }

    @Test("A sequence extension of a content base compiles")
    func test_sequenceExtensionAccepted() {
        #expect(compiles(seqBase + ext(base: "myType", content: "<xs:sequence><xs:element name=\"b\" type=\"xs:string\"/></xs:sequence>")))
    }

    @Test("An all group as the whole content of a complex type compiles")
    func test_allAsWholeContentAccepted() {
        #expect(compiles("<xs:complexType name=\"t\">\(allContent)</xs:complexType>"))
    }

    /// A base whose content is an explicit but empty model group (`<xs:sequence/>`)
    /// has effectively empty content, so extending it with an `all` makes the `all`
    /// the whole content model, which is valid (W3C Bug 6202).
    @Test("An all group extending an explicitly-empty (non-mixed) base compiles")
    func test_allExtendingExplicitEmptyAccepted() {
        let base = "<xs:complexType name=\"emptyGroup\"><xs:sequence/></xs:complexType>"
        #expect(compiles(base + ext(base: "emptyGroup", content: allContent)))
    }

    /// A mixed base, even with an empty particle, may not be extended by an `all`
    /// (the resolution of W3C Bug 6202 keeps this invalid).
    @Test("An all group extending a mixed empty base is rejected")
    func test_allExtendingMixedEmptyRejected() {
        let base = "<xs:complexType name=\"mixedEmpty\" mixed=\"true\"><xs:sequence/></xs:complexType>"
        #expect(!compiles(base + ext(base: "mixedEmpty", content: allContent)))
    }

    private let simpleBase = "<xs:complexType name=\"simpleC\"><xs:simpleContent>"
        + "<xs:extension base=\"xs:string\"><xs:attribute name=\"a\" type=\"xs:string\"/></xs:extension>"
        + "</xs:simpleContent></xs:complexType>"

    private func simpleExt(base: String) -> String {
        "<xs:complexType name=\"fooType\"><xs:simpleContent>"
            + "<xs:extension base=\"\(base)\"/></xs:simpleContent></xs:complexType>"
    }

    /// src-ct.1: a complexContent base must be a complex type. A user simpleType or
    /// an XSD built-in simple type (`xs:string`) is rejected; the complex ur-type
    /// `xs:anyType` and a user complex type are valid bases.
    @Test("a complexContent base must be a complex type (src-ct.1)")
    func test_complexContentBaseKind() {
        let simpleType = "<xs:simpleType name=\"st\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
        #expect(!compiles(simpleType + ext(base: "st", content: allContent)))
        #expect(!compiles(ext(base: "xs:string", content: allContent)))
        // anyType is complex (the ur-type) and a user complex base are valid.
        #expect(compiles(ext(base: "xs:anyType", content: allContent)))
        #expect(compiles(seqBase + ext(base: "myType", content: "<xs:sequence><xs:element name=\"b\" type=\"xs:string\"/></xs:sequence>")))
    }

    /// src-ct.2 (extension): a simpleContent extension base must be a simple type or
    /// a complex type with simple content. A complex type with element-only or mixed
    /// content, or `xs:anyType`, is rejected; a simple type or a simple-content
    /// complex type is valid.
    @Test("a simpleContent extension base must have simple content (src-ct.2)")
    func test_simpleContentExtensionBaseKind() {
        // anyType (complex content) and an element-only complex type are invalid.
        #expect(!compiles(simpleExt(base: "xs:anyType")))
        #expect(!compiles(seqBase + simpleExt(base: "myType")))
        let mixed = "<xs:complexType name=\"m\" mixed=\"true\"><xs:sequence/></xs:complexType>"
        #expect(!compiles(mixed + simpleExt(base: "m")))
        // A simple-type base, and a complex type with simple content, are valid.
        #expect(compiles(simpleExt(base: "xs:string")))
        #expect(compiles(simpleBase + simpleExt(base: "simpleC")))
    }

    /// A schema may target the XSD namespace and define its own components there (as
    /// the schema-for-schemas does, extending its own complex `openAttrs`). A
    /// locally-declared type must take precedence over the built-in reading, so such
    /// a complexContent extension of a local complex type is not rejected.
    @Test("a schema targeting the XSD namespace may extend its own complex types")
    func test_localTypePrecedenceOverBuiltin() {
        let document = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="openAttrs"><xs:complexContent><xs:restriction base="xs:anyType">
            <xs:anyAttribute namespace="##other"/></xs:restriction></xs:complexContent></xs:complexType>
          <xs:complexType name="annotated"><xs:complexContent><xs:extension base="xs:openAttrs">
            <xs:sequence><xs:element name="annotation" minOccurs="0"/></xs:sequence></xs:extension></xs:complexContent></xs:complexType>
        </xs:schema>
        """
        #expect((try? PureXML.Schema.Document(document)) != nil)
    }

    /// cos-valid-default: an element with a `default`/`fixed` value constraint needs
    /// simple or mixed content. An element-only type (inline or named) is rejected;
    /// a simple type, `xs:anyType` (mixed), an untyped element (anyType), a mixed or
    /// simple-content complex type, all stay valid.
    @Test("an element value constraint requires simple or mixed content (cos-valid-default)")
    func test_valueConstraintContentType() {
        // Inline element-only complex type with a fixed value (elemG003/elemG004).
        #expect(!compiles("<xs:element name=\"e\" fixed=\"foo\"><xs:complexType>\(allContent)</xs:complexType></xs:element>"))
        // Named element-only complex type with a default value (elemD004).
        #expect(!compiles(seqBase + "<xs:element name=\"e\" type=\"myType\" default=\"foo\"/>"))
        // Valid: a simple type, the ur-type, an untyped (anyType) element.
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\" fixed=\"foo\"/>"))
        #expect(compiles("<xs:element name=\"e\" type=\"xs:anyType\" fixed=\"foo\"/>"))
        #expect(compiles("<xs:element name=\"e\" default=\"foo\"/>"))
        // Valid: a complex type with simple content, and a mixed complex type.
        #expect(compiles(simpleBase + "<xs:element name=\"e\" type=\"simpleC\" fixed=\"foo\"/>"))
        let mixedType = "<xs:complexType name=\"mx\" mixed=\"true\"><xs:sequence/></xs:complexType>"
        #expect(compiles(mixedType + "<xs:element name=\"e\" type=\"mx\" default=\"foo\"/>"))
    }
}
