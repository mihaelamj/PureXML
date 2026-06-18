import Testing
@testable import PureXML

@Suite("XSD type attribute excludes an inline type")
struct SchemaTypeExclusivityTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("type attribute and an inline type definition are mutually exclusive")
    func test_typeAndInlineTypeRejected() {
        // Element with both type= and an inline simpleType (src-element.3).
        #expect(!compiles("<xs:element name=\"e\" type=\"xs:string\"><xs:simpleType>"
                + "<xs:restriction base=\"xs:string\"/></xs:simpleType></xs:element>"))
        // Element with both type= and an inline complexType.
        #expect(!compiles("<xs:element name=\"e\" type=\"xs:string\"><xs:complexType><xs:sequence/></xs:complexType></xs:element>"))
        // Attribute with both type= and an inline simpleType (src-attribute.3.1).
        #expect(!compiles("<xs:complexType name=\"T\"><xs:attribute name=\"a\" type=\"xs:string\">"
                + "<xs:simpleType><xs:restriction base=\"xs:string\"/></xs:simpleType></xs:attribute></xs:complexType>"))
    }

    @Test("type alone, or an inline type alone, compiles")
    func test_eitherAloneAccepted() {
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\"/>"))
        #expect(compiles("<xs:element name=\"e\"><xs:simpleType><xs:restriction base=\"xs:string\"/></xs:simpleType></xs:element>"))
        #expect(compiles("<xs:complexType name=\"T\"><xs:attribute name=\"a\" type=\"xs:string\"/></xs:complexType>"))
        // type= alongside an identity constraint (not a type) is legal.
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\"><xs:unique name=\"u\"><xs:selector xpath=\".\"/><xs:field xpath=\"@x\"/></xs:unique></xs:element>"))
    }

    @Test("A foreign-namespace child named simpleType/complexType is not the component's inline type")
    func test_foreignNamespaceChildNotInlineType() {
        // A foreign child whose local name happens to be complexType is not an XSD
        // inline type, so type= alongside it is not the type/inline-type clash.
        let schema = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:foo=\"urn:foo\">"
            + "<xs:element name=\"e\" type=\"xs:string\"><foo:complexType/></xs:element></xs:schema>"
        #expect((try? PureXML.Schema.Document(schema)) != nil)
    }
}
