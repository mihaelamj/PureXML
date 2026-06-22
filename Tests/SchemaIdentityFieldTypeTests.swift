import Testing
@testable import PureXML

/// cvc-identity-constraint.3 / c-fields-xpaths: an identity-constraint field must
/// identify a node with a simple type (a simple-typed element, an element with simple
/// content, or an attribute). A field whose target is a complex type with non-simple
/// content is invalid, whether the instance node has element children (idK012) or is
/// empty/attributes-only (idG006). A simple or simpleContent target stays valid.
@Suite("XSD identity-constraint field simple-content")
struct SchemaIdentityFieldTypeTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    private let head = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"

    @Test("a field selecting a complex-content element is rejected (idK012)")
    func test_fieldWithElementChildrenRejected() throws {
        let complexField = """
        \(head)
          <xs:element name="root">
            <xs:complexType><xs:sequence>
              <xs:element name="uid" maxOccurs="unbounded"><xs:complexType><xs:sequence>
                <xs:element name="pid"><xs:complexType><xs:sequence><xs:element name="gid"/></xs:sequence></xs:complexType></xs:element>
              </xs:sequence></xs:complexType></xs:element>
            </xs:sequence></xs:complexType>
            <xs:key name="k"><xs:selector xpath=".//uid"/><xs:field xpath="pid"/></xs:key>
          </xs:element>
        </xs:schema>
        """
        #expect(try !validate(complexField, "<root><uid><pid><gid>x</gid></pid></uid></root>").isEmpty)
        let simpleField = """
        \(head)
          <xs:element name="root">
            <xs:complexType><xs:sequence>
              <xs:element name="uid" maxOccurs="unbounded"><xs:complexType><xs:sequence>
                <xs:element name="pid" type="xs:string"/>
              </xs:sequence></xs:complexType></xs:element>
            </xs:sequence></xs:complexType>
            <xs:key name="k"><xs:selector xpath=".//uid"/><xs:field xpath="pid"/></xs:key>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(simpleField, "<root><uid><pid>a</pid></uid><uid><pid>b</pid></uid></root>").isEmpty)
    }

    @Test("a field whose declared type is an empty/attributes-only complex type is rejected (idG006)")
    func test_emptyComplexFieldRejected() throws {
        let emptyComplex = """
        \(head)
          <xs:element name="root">
            <xs:complexType><xs:sequence><xs:element ref="uid" maxOccurs="unbounded"/></xs:sequence></xs:complexType>
            <xs:key name="uuid"><xs:selector xpath=".//uid"/><xs:field xpath="pid"/></xs:key>
          </xs:element>
          <xs:element name="uid"><xs:complexType><xs:sequence>
            <xs:element name="pid"><xs:complexType><xs:attribute name="p" type="xs:string"/></xs:complexType></xs:element>
          </xs:sequence><xs:attribute name="val" type="xs:string"/></xs:complexType></xs:element>
        </xs:schema>
        """
        #expect(try !validate(emptyComplex, "<root><uid val=\"1\"><pid p=\"11\"/></uid></root>").isEmpty)
        let simpleContent = """
        \(head)
          <xs:element name="root">
            <xs:complexType><xs:sequence><xs:element ref="uid" maxOccurs="unbounded"/></xs:sequence></xs:complexType>
            <xs:key name="uuid"><xs:selector xpath=".//uid"/><xs:field xpath="pid"/></xs:key>
          </xs:element>
          <xs:element name="uid"><xs:complexType><xs:sequence>
            <xs:element name="pid"><xs:complexType><xs:simpleContent><xs:extension base="xs:string">
              <xs:attribute name="p" type="xs:string"/></xs:extension></xs:simpleContent></xs:complexType></xs:element>
          </xs:sequence></xs:complexType></xs:element>
        </xs:schema>
        """
        #expect(try validate(simpleContent, "<root><uid><pid p=\"1\">a</pid></uid></root>").isEmpty)
    }
}
