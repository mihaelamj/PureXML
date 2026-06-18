import Testing
@testable import PureXML

@Suite("Schema structural derivation validity")
struct SchemaStructureDerivationTests {
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

    @Test("a complexContent derivation's content must be ordered: model group, attributes, anyAttribute")
    func test_complexContentDerivationOrder() {
        func derive(_ kind: String, _ body: String) -> String {
            #"""
            <xs:complexType name="b"><xs:sequence><xs:element name="e" type="xs:string"/></xs:sequence></xs:complexType>
            <xs:complexType name="t"><xs:complexContent><xs:\#(kind) base="b">\#(body)</xs:\#(kind)></xs:complexContent></xs:complexType>
            """#
        }
        // Two model groups (ctG/ctH "X then Y").
        #expect(rejects(derive("restriction", #"<xs:sequence/><xs:sequence/>"#)))
        #expect(rejects(derive("extension", #"<xs:choice/><xs:all/>"#)))
        // A model group after an attribute.
        #expect(rejects(derive("restriction", #"<xs:attribute name="x"/><xs:sequence/>"#)))
        // An attribute after anyAttribute, and two anyAttributes.
        #expect(rejects(derive("extension", #"<xs:anyAttribute/><xs:attribute name="x"/>"#)))
        #expect(rejects(derive("restriction", #"<xs:sequence/><xs:anyAttribute/><xs:anyAttribute/>"#)))
    }

    @Test("a well-ordered complexContent derivation compiles")
    func test_complexContentDerivationValid() throws {
        try compile(#"""
        <xs:complexType name="b"><xs:sequence><xs:element name="e" type="xs:string"/></xs:sequence></xs:complexType>
        <xs:complexType name="t"><xs:complexContent>
          <xs:extension base="b">
            <xs:sequence><xs:element name="f" type="xs:string"/></xs:sequence>
            <xs:attribute name="x" type="xs:string"/>
            <xs:anyAttribute/>
          </xs:extension>
        </xs:complexContent></xs:complexType>
        """#)
        // No model group is fine (an extension that only adds attributes).
        try compile(#"""
        <xs:complexType name="b"><xs:sequence><xs:element name="e" type="xs:string"/></xs:sequence></xs:complexType>
        <xs:complexType name="t"><xs:complexContent>
          <xs:extension base="b"><xs:attribute name="x" type="xs:string"/></xs:extension>
        </xs:complexContent></xs:complexType>
        """#)
    }

    @Test("a complexType's shorthand content must be ordered: model group, attributes, anyAttribute")
    func test_complexTypeShorthandOrder() {
        // A model group after an attribute, two anyAttributes, an attribute after anyAttribute (ctB).
        #expect(rejects(#"<xs:complexType name="t"><xs:attribute name="x"/><xs:sequence/></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="t"><xs:all/><xs:anyAttribute/><xs:anyAttribute/></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="t"><xs:anyAttribute/><xs:attribute name="x"/></xs:complexType>"#))
        // A well-ordered shorthand complexType compiles.
        #expect(!rejects(#"""
        <xs:complexType name="t">
          <xs:sequence><xs:element name="e" type="xs:string"/></xs:sequence>
          <xs:attribute name="x" type="xs:string"/>
          <xs:anyAttribute/>
        </xs:complexType>
        """#))
    }

    @Test("a simpleType must contain exactly one of restriction, list, or union")
    func test_simpleTypeContent() {
        // Two derivations, or a mix, is invalid (stB).
        #expect(rejects(#"<xs:simpleType name="t"><xs:list itemType="xs:int"/><xs:list itemType="xs:int"/></xs:simpleType>"#))
        #expect(rejects(#"<xs:simpleType name="t"><xs:union memberTypes="xs:int"/><xs:restriction base="xs:string"/></xs:simpleType>"#))
        #expect(rejects(#"<xs:simpleType name="t"></xs:simpleType>"#))
        // Exactly one compiles.
        #expect(!rejects(#"<xs:simpleType name="t"><xs:restriction base="xs:string"/></xs:simpleType>"#))
        #expect(!rejects(#"<xs:simpleType name="t"><xs:list itemType="xs:int"/></xs:simpleType>"#))
    }

    @Test("documentation xml:lang and xml:space validation")
    func test_documentationXmlAttributes() throws {
        // Valid xml:lang and xml:space
        try compile(#"""
        <xs:annotation>
          <xs:documentation xml:lang="en" xml:space="preserve">Valid documentation</xs:documentation>
        </xs:annotation>
        """#)

        // Invalid xml:lang (empty)
        #expect(rejects(#"""
        <xs:annotation>
          <xs:documentation xml:lang="">Invalid documentation</xs:documentation>
        </xs:annotation>
        """#))

        // Invalid xml:lang (whitespace only)
        #expect(rejects(#"""
        <xs:annotation>
          <xs:documentation xml:lang=" ">Invalid documentation</xs:documentation>
        </xs:annotation>
        """#))

        // Invalid xml:space
        #expect(rejects(#"""
        <xs:annotation>
          <xs:documentation xml:space="invalid">Invalid documentation</xs:documentation>
        </xs:annotation>
        """#))
    }
}
