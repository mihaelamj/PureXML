@testable import PureXML
import Testing

/// Structural validity of a schema document against the schema-for-schemas
/// content model (XSD 1.0 Structures): each component's children must be
/// admitted by the model, an `annotation` (where allowed once) must be first,
/// and an identity constraint needs a selector and field. Such a schema is
/// invalid and must be rejected at compile time; the children were previously
/// unchecked and the schema accepted (XSTS invalid-schema ctB/ctG/ctH, etc.).
@Suite("Schema structural validity")
struct SchemaStructureTests {
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

    @Test("well-formed components compile")
    func test_valid() throws {
        try compile(#"""
        <xs:complexType name="t">
          <xs:annotation><xs:documentation>doc</xs:documentation></xs:annotation>
          <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          <xs:attribute name="x" type="xs:string"/>
        </xs:complexType>
        """#)
        try compile(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="@id"/></xs:key>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="id" type="xs:string"/></xs:complexType></xs:element>
        """#)
    }

    @Test("a child not admitted by the content model is rejected")
    func test_disallowedChild() {
        // element is not a direct child of complexType (it must sit in a group).
        #expect(rejects(#"<xs:complexType name="t"><xs:element name="a" type="xs:string"/></xs:complexType>"#))
        // attribute admits only annotation and simpleType, not sequence.
        #expect(rejects(#"<xs:attribute name="a"><xs:sequence/></xs:attribute>"#))
    }

    @Test("at most one annotation, and it must be first")
    func test_annotationPlacement() {
        #expect(rejects(#"""
        <xs:complexType name="t">
          <xs:annotation><xs:documentation>one</xs:documentation></xs:annotation>
          <xs:annotation><xs:documentation>two</xs:documentation></xs:annotation>
        </xs:complexType>
        """#))
        #expect(rejects(#"""
        <xs:complexType name="t">
          <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          <xs:annotation><xs:documentation>late</xs:documentation></xs:annotation>
        </xs:complexType>
        """#))
    }

    @Test("schema and redefine may carry several annotations")
    func test_multipleAnnotationOnSchema() throws {
        try compile(#"""
        <xs:annotation><xs:documentation>one</xs:documentation></xs:annotation>
        <xs:element name="a" type="xs:string"/>
        <xs:annotation><xs:documentation>two</xs:documentation></xs:annotation>
        """#)
    }

    @Test("enumerated attributes accept only their value space")
    func test_enumeratedAttributeValues() {
        #expect(rejects(#"<xs:attribute name="a" type="xs:string" use="foo"/>"#))
        #expect(rejects(#"<xs:attribute name="a" type="xs:string" use=""/>"#))
        #expect(rejects(#"<xs:complexType name="t" mixed="yes"><xs:sequence/></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="t" abstract="maybe"><xs:sequence/></xs:complexType>"#))
        #expect(rejects(#"<xs:element name="a" type="xs:string" form="Qualified"/>"#))
    }

    @Test("minOccurs and maxOccurs must be nonNegativeInteger (maxOccurs also unbounded)")
    func test_occursValues() throws {
        try compile(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string" minOccurs="0" maxOccurs="unbounded"/></xs:sequence></xs:complexType>"#)
        #expect(rejects(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string" minOccurs="-1"/></xs:sequence></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string" maxOccurs="lots"/></xs:sequence></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string" minOccurs="x"/></xs:sequence></xs:complexType>"#))
    }

    @Test("a particle's minOccurs may not exceed its maxOccurs")
    func test_occurrenceOrder() throws {
        func wrap(_ particle: String) -> String {
            "<xs:complexType name=\"t\"><xs:sequence>\(particle)</xs:sequence></xs:complexType>"
        }
        #expect(rejects(wrap(#"<xs:element name="a" type="xs:string" minOccurs="5" maxOccurs="2"/>"#)))
        #expect(rejects(wrap(#"<xs:element name="a" type="xs:string" minOccurs="3" maxOccurs="0"/>"#)))
        // Equal bounds, and unbounded, are fine.
        try compile(wrap(#"<xs:element name="a" type="xs:string" minOccurs="2" maxOccurs="2"/>"#))
        try compile(wrap(#"<xs:element name="a" type="xs:string" minOccurs="2" maxOccurs="unbounded"/>"#))
        try compile(wrap(#"<xs:element name="a" type="xs:string" minOccurs="0" maxOccurs="0"/>"#))
    }

    @Test("valid enumerated and occurrence attribute values compile")
    func test_validAttributeValues() throws {
        // `use` is valid on a local attribute use, not on a top-level declaration.
        try compile(#"<xs:complexType name="t"><xs:attribute name="a" type="xs:string" use="required"/></xs:complexType>"#)
        try compile(#"<xs:complexType name="t" mixed="true"><xs:sequence/></xs:complexType>"#)
        try compile(#"<xs:complexType name="t" abstract="false"><xs:sequence/></xs:complexType>"#)
    }

    @Test("a component name must be a valid NCName")
    func test_nameNCName() {
        #expect(rejects(#"<xs:element name="" type="xs:string"/>"#))
        #expect(rejects(#"<xs:element name="123" type="xs:string"/>"#))
        #expect(rejects(#"<xs:complexType name="a:b"><xs:sequence/></xs:complexType>"#))
        #expect(rejects(#"<xs:attribute name="a b" type="xs:string"/>"#))
        try? compile(#"<xs:element name="_ok-1.2" type="xs:string"/>"#)
    }

    @Test("a QName-valued reference attribute must be a lexical QName")
    func test_qnameReferences() throws {
        #expect(rejects(#"<xs:element name="a" type=":_"/>"#))
        #expect(rejects(#"<xs:element name="a" type="a:b:c"/>"#))
        try compile(#"<xs:element name="a" type="xs:string"/>"#)
        try compile(#"<xs:complexType name="t"><xs:sequence><xs:element ref="g"/></xs:sequence></xs:complexType><xs:element name="g" type="xs:string"/>"#)
    }

    @Test("a complexType's content shape is exclusive")
    func test_complexTypeContentExclusivity() {
        // simpleContent/complexContent are mutually exclusive and exclude a model
        // group or a direct attribute; only one model group is allowed.
        #expect(rejects(#"""
        <xs:complexType name="t">
          <xs:simpleContent><xs:extension base="xs:string"/></xs:simpleContent>
          <xs:simpleContent><xs:extension base="xs:string"/></xs:simpleContent>
        </xs:complexType>
        """#))
        #expect(rejects(#"""
        <xs:complexType name="t">
          <xs:simpleContent><xs:extension base="xs:string"/></xs:simpleContent>
          <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
        </xs:complexType>
        """#))
        #expect(rejects(#"""
        <xs:complexType name="t">
          <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          <xs:choice><xs:element name="b" type="xs:string"/></xs:choice>
        </xs:complexType>
        """#))
    }

    @Test("valid complexType content shapes compile")
    func test_complexTypeContentValid() throws {
        try compile(#"""
        <xs:complexType name="t">
          <xs:simpleContent><xs:extension base="xs:string"><xs:attribute name="a" type="xs:string"/></xs:extension></xs:simpleContent>
        </xs:complexType>
        """#)
        try compile(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence><xs:attribute name="x" type="xs:string"/></xs:complexType>"#)
        try compile(#"<xs:complexType name="t"><xs:attribute name="x" type="xs:string"/></xs:complexType>"#)
    }

    @Test("a named group must contain exactly one model group")
    func test_namedGroupContent() throws {
        try compile(#"<xs:group name="g"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:group>"#)
        // Two compositors, or none, is invalid.
        #expect(rejects(#"""
        <xs:group name="g">
          <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          <xs:all><xs:element name="b" type="xs:string"/></xs:all>
        </xs:group>
        """#))
        #expect(rejects(#"<xs:group name="g"><xs:annotation><xs:documentation>x</xs:documentation></xs:annotation></xs:group>"#))
        // A group reference (no name) is not a definition and is not flagged here.
        try compile(
            #"<xs:group name="g"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:group><xs:complexType name="t"><xs:group ref="g"/></xs:complexType>"#,
        )
    }

    @Test("an attribute not admitted by a component is rejected")
    func test_attributeApplicability() {
        #expect(rejects(#"<xs:element name="a" type="xs:string" nullable="true"/>"#)) // typo for nillable
        #expect(rejects(#"<xs:complexType name="t" foo="bar"><xs:sequence/></xs:complexType>"#))
        #expect(rejects(#"<xs:sequence name="x"/>"#)) // sequence has no name
        // A foreign-namespace attribute is allowed.
        try? compile(#"<xs:element name="a" type="xs:string" xmlns:x="urn:x" x:note="hi"/>"#)
    }

    @Test("ref excludes name and type")
    func test_refExclusions() {
        #expect(rejects(#"<xs:complexType name="t"><xs:sequence><xs:element ref="g" name="h"/></xs:sequence></xs:complexType><xs:element name="g" type="xs:string"/>"#))
        #expect(rejects(#"<xs:complexType name="t"><xs:sequence><xs:element ref="g" type="xs:string"/></xs:sequence></xs:complexType><xs:element name="g" type="xs:string"/>"#))
    }

    @Test("element declarations in one content model must be consistent")
    func test_elementDeclsConsistent() throws {
        // Same name, different type in one content model is invalid.
        #expect(rejects(#"""
        <xs:complexType name="t"><xs:sequence>
          <xs:element name="a" type="xs:string"/>
          <xs:element name="a" type="xs:integer"/>
        </xs:sequence></xs:complexType>
        """#))
        // Same name, same type is consistent (separated so it stays unambiguous).
        try compile(#"""
        <xs:complexType name="t"><xs:sequence>
          <xs:element name="a" type="xs:string"/>
          <xs:element name="b" type="xs:string"/>
          <xs:element name="a" type="xs:string"/>
        </xs:sequence></xs:complexType>
        """#)
        // A same name in a NESTED complex type is a different content model: allowed.
        try compile(#"""
        <xs:complexType name="t"><xs:sequence>
          <xs:element name="a" type="xs:string"/>
          <xs:element name="b">
            <xs:complexType><xs:sequence><xs:element name="a" type="xs:integer"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:sequence></xs:complexType>
        """#)
    }

    @Test("an identity constraint requires a selector and field")
    func test_identityConstraintRequiresParts() {
        #expect(rejects(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:key name="k"><xs:selector xpath="a"/></xs:key>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="id" type="xs:string"/></xs:complexType></xs:element>
        """#))
    }

    @Test("schema elements must follow order: imports/includes/redefines before declarations")
    func test_schemaChildrenOrder() throws {
        // Redefine after element is rejected
        #expect(rejects(#"""
        <xs:element name="t" type="xs:string" />
        <xs:redefine schemaLocation="redefinebug.red">
            <xs:complexType name="tabletype"><xs:sequence/></xs:complexType>
        </xs:redefine>
        """#))
        // Import after element is rejected
        #expect(rejects(#"""
        <xs:element name="t" type="xs:string" />
        <xs:import namespace="http://example.com/other" schemaLocation="some.imp" />
        """#))
        // Include after element is rejected
        #expect(rejects(#"""
        <xs:element name="t" type="xs:string" />
        <xs:include schemaLocation="some.inc" />
        """#))
        // Correct order is compiled successfully
        try compile(#"""
        <xs:import namespace="http://example.com/other" schemaLocation="some.imp" />
        <xs:element name="t" type="xs:string" />
        """#)
    }

    @Test("import constraints: namespace attribute presence and matching targetNamespace")
    func test_importConstraints() throws {
        // Import without namespace attribute in a schema with NO targetNamespace is rejected
        #expect(rejects(#"<xs:import schemaLocation="test.imp" />"#))

        // Import whose namespace is the same as the targetNamespace is rejected
        #expect(throws: Error.self) {
            _ = try PureXML.Schema.Document(#"""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="http://example.com">
                <xs:import namespace="http://example.com" schemaLocation="test.imp" />
            </xs:schema>
            """#)
        }
    }
}

@Suite("Schema structural order and cardinality validity")
struct SchemaStructureOrderTests {
    private func compile(_ body: String) throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        \(body)
        </xs:schema>
        """)
    }

    private func rejects(_ body: String) -> Bool {
        do {
            try compile(body)
            return false
        } catch {
            return true
        }
    }

    @Test("element child order and type exclusivity constraints")
    func test_elementChildOrderAndExclusivity() throws {
        // More than one type definition is rejected
        #expect(rejects(#"""
        <xs:element name="root">
          <xs:simpleType><xs:restriction base="xs:string"/></xs:simpleType>
          <xs:complexType><xs:sequence/></xs:complexType>
        </xs:element>
        """#))

        // Type definition after identity constraints is rejected
        #expect(rejects(#"""
        <xs:element name="root">
          <xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="@id"/></xs:key>
          <xs:complexType><xs:sequence/></xs:complexType>
        </xs:element>
        """#))

        // Correct order compiles successfully
        try compile(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence/></xs:complexType>
          <xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="@id"/></xs:key>
        </xs:element>
        """#)
    }

    @Test("attribute child cardinality constraints")
    func test_attributeChildCardinality() {
        // More than one simpleType is rejected
        #expect(rejects(#"""
        <xs:attribute name="a">
          <xs:simpleType><xs:restriction base="xs:string"/></xs:simpleType>
          <xs:simpleType><xs:restriction base="xs:integer"/></xs:simpleType>
        </xs:attribute>
        """#))
    }

    @Test("attributeGroup child order and cardinality constraints")
    func test_attributeGroupChildOrderAndCardinality() throws {
        // More than one anyAttribute is rejected
        #expect(rejects(#"""
        <xs:attributeGroup name="myGroup">
          <xs:anyAttribute namespace="##any"/>
          <xs:anyAttribute namespace="##other"/>
        </xs:attributeGroup>
        """#))

        // Attribute reference after anyAttribute is rejected
        #expect(rejects(#"""
        <xs:attributeGroup name="myGroup">
          <xs:anyAttribute namespace="##any"/>
          <xs:attribute name="x" type="xs:string"/>
        </xs:attributeGroup>
        """#))

        // Correct order compiles successfully
        try compile(#"""
        <xs:attributeGroup name="myGroup">
          <xs:attribute name="x" type="xs:string"/>
          <xs:anyAttribute namespace="##any"/>
        </xs:attributeGroup>
        """#)
    }

    @Test("group compositor cardinality constraints")
    func test_groupCompositorCardinality() {
        // More than one compositor is rejected
        #expect(rejects(#"""
        <xs:group name="myGroup">
          <xs:sequence/>
          <xs:choice/>
        </xs:group>
        """#))
    }
}
