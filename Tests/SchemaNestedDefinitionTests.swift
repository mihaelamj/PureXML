import Testing
@testable import PureXML

@Suite("XSD nested definitions may not be named (localSimpleType / attributeGroup ref)")
struct SchemaNestedDefinitionTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("A nested simpleType with a name is rejected")
    func test_nestedNamedSimpleTypeRejected() {
        #expect(!compiles(
            "<xs:simpleType name=\"parent\"><xs:restriction>"
                + "<xs:simpleType name=\"foo\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
                + "</xs:restriction></xs:simpleType>",
        ))
    }

    @Test("A nested attributeGroup definition with a name is rejected")
    func test_nestedNamedAttributeGroupRejected() {
        #expect(!compiles(
            "<xs:attributeGroup name=\"G\">"
                + "<xs:attributeGroup name=\"abc\"><xs:attribute name=\"a\" type=\"xs:string\"/></xs:attributeGroup>"
                + "</xs:attributeGroup>",
        ))
    }

    @Test("A nested anonymous simpleType compiles")
    func test_nestedAnonymousSimpleTypeAccepted() {
        #expect(compiles(
            "<xs:element name=\"e\"><xs:simpleType><xs:restriction base=\"xs:string\"/></xs:simpleType></xs:element>",
        ))
        #expect(compiles(
            "<xs:simpleType name=\"L\"><xs:list><xs:simpleType><xs:restriction base=\"xs:string\"/></xs:simpleType></xs:list></xs:simpleType>",
        ))
    }

    @Test("A nested attributeGroup reference and top-level named definitions compile")
    func test_refAndTopLevelAccepted() {
        #expect(compiles(
            "<xs:attributeGroup name=\"G\"><xs:attribute name=\"a\" type=\"xs:string\"/></xs:attributeGroup>"
                + "<xs:complexType name=\"T\"><xs:attributeGroup ref=\"G\"/></xs:complexType>",
        ))
        #expect(compiles("<xs:simpleType name=\"S\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"))
    }
}
