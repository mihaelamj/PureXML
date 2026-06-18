import Testing
@testable import PureXML

@Suite("XSD ID-typed declarations have no value constraint")
struct SchemaIDValueConstraintTests {
    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">\(body)</xs:schema>")) != nil
    }

    @Test("An ID-typed attribute or element with a default or fixed value is rejected")
    func test_idWithValueConstraintRejected() {
        // Attribute of type xs:ID with a fixed value (a-props-correct.3).
        #expect(!compiles("<xs:complexType name=\"T\"><xs:attribute name=\"a\" type=\"xs:ID\" fixed=\"x\"/></xs:complexType>"))
        // Element of type xs:ID with a default value (e-props-correct.5).
        #expect(!compiles("<xs:element name=\"e\" type=\"xs:ID\" default=\"x\"/>"))
        // A named user type derived from xs:ID is recognized (the check runs after
        // named types resolve).
        #expect(!compiles("<xs:simpleType name=\"myID\"><xs:restriction base=\"xs:ID\"/></xs:simpleType>"
                + "<xs:complexType name=\"T\"><xs:attribute name=\"a\" type=\"myID\" fixed=\"x\"/></xs:complexType>"))
    }

    @Test("An ID-typed declaration without a value constraint, or a value constraint on a non-ID type, compiles")
    func test_acceptedCases() {
        // ID type, no value constraint.
        #expect(compiles("<xs:complexType name=\"T\"><xs:attribute name=\"a\" type=\"xs:ID\"/></xs:complexType>"))
        #expect(compiles("<xs:element name=\"e\" type=\"xs:ID\"/>"))
        // A value constraint on a non-ID type is fine.
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\" default=\"x\"/>"))
        #expect(compiles("<xs:complexType name=\"T\"><xs:attribute name=\"a\" type=\"xs:string\" fixed=\"x\"/></xs:complexType>"))
    }

    @Test("A user type named ID (not xs:ID) with a value constraint is allowed")
    func test_userTypeNamedIDNotBuiltin() {
        // A user simpleType named ID in the target namespace, derived from string, is
        // not the built-in xs:ID: a value constraint on it is legal. Resolving by
        // local name alone would wrongly reject it.
        let schema = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""
            + " targetNamespace=\"urn:t\" xmlns:t=\"urn:t\">"
            + "<xs:simpleType name=\"ID\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
            + "<xs:element name=\"e\" type=\"t:ID\" default=\"x\"/></xs:schema>"
        #expect((try? PureXML.Schema.Document(schema)) != nil)
    }
}
