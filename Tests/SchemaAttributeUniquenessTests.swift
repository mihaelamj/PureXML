@testable import PureXML
import Testing

@Suite("XSD attribute-use uniqueness and single ID")
struct SchemaAttributeUniquenessTests {
    private func compiles(_ source: String) -> Bool {
        (try? PureXML.Schema.Document(source)) != nil
    }

    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    @Test("Two attribute uses with the same name in one type or group are rejected")
    func test_duplicateAttributeRejected() {
        // Two local attributes of the same name directly in a complex type.
        #expect(!compiles("<xs:schema \(xsd)><xs:complexType name=\"T\">"
                + "<xs:attribute name=\"a\" type=\"xs:string\"/><xs:attribute name=\"a\" type=\"xs:int\"/>"
                + "</xs:complexType></xs:schema>"))
        // A local attribute colliding with one pulled in through an attribute group.
        #expect(!compiles("<xs:schema \(xsd)>"
                + "<xs:attributeGroup name=\"g\"><xs:attribute name=\"a\" type=\"xs:string\"/></xs:attributeGroup>"
                + "<xs:complexType name=\"T\"><xs:attribute name=\"a\" type=\"xs:int\"/><xs:attributeGroup ref=\"g\"/></xs:complexType></xs:schema>"))
        // Two same-named attributes within one attribute group (ag-props-correct.2).
        #expect(!compiles("<xs:schema \(xsd)><xs:attributeGroup name=\"g\">"
                + "<xs:attribute name=\"a\"/><xs:attribute name=\"a\"/></xs:attributeGroup></xs:schema>"))
    }

    @Test("More than one ID-typed attribute is rejected (ct-props-correct.5)")
    func test_twoIDAttributesRejected() {
        #expect(!compiles("<xs:schema \(xsd)><xs:complexType name=\"T\">"
                + "<xs:attribute name=\"a\" type=\"xs:ID\"/><xs:attribute name=\"b\" type=\"xs:ID\"/>"
                + "</xs:complexType></xs:schema>"))
        // A single ID attribute is fine.
        #expect(compiles("<xs:schema \(xsd)><xs:complexType name=\"T\">"
                + "<xs:attribute name=\"a\" type=\"xs:ID\"/><xs:attribute name=\"b\" type=\"xs:string\"/>"
                + "</xs:complexType></xs:schema>"))
    }

    @Test("Same local name in different namespaces, and a diamond, are not clashes")
    func test_distinctNamespacesAndDiamondAccepted() {
        // attQ010/attQ019: a local attribute and a reference to a same-local-name
        // attribute in an imported namespace are different attributes. (Must compile.)
        #expect(compiles("<xs:schema \(xsd) targetNamespace=\"urn:t\" xmlns:t=\"urn:t\""
                + " xmlns:imp=\"urn:imp\" attributeFormDefault=\"qualified\">"
                + "<xs:import namespace=\"urn:imp\"/>"
                + "<xs:attributeGroup name=\"g\"><xs:attribute name=\"a\"/><xs:attribute ref=\"imp:a\"/></xs:attributeGroup>"
                + "<xs:complexType name=\"T\"><xs:attributeGroup ref=\"t:g\"/></xs:complexType></xs:schema>"))
        // A diamond of attribute-group references reaching the same attribute once is
        // not a duplicate: g3 has attribute a; g1 and g2 both include g3; T includes
        // both. (Must compile.)
        #expect(compiles("<xs:schema \(xsd)>"
                + "<xs:attributeGroup name=\"g3\"><xs:attribute name=\"a\"/></xs:attributeGroup>"
                + "<xs:attributeGroup name=\"g1\"><xs:attributeGroup ref=\"g3\"/></xs:attributeGroup>"
                + "<xs:attributeGroup name=\"g2\"><xs:attributeGroup ref=\"g3\"/></xs:attributeGroup>"
                + "<xs:complexType name=\"T\"><xs:attributeGroup ref=\"g1\"/><xs:attributeGroup ref=\"g2\"/></xs:complexType></xs:schema>"))
    }
}
