@testable import PureXML
import Testing

/// cvc-elt.4.3.2.1 for a list or union `xsi:type`: a list or union simple type
/// derives only from `anySimpleType`, so it can validly stand in only for an
/// element whose declared type is a ur-type. Naming a list or union type on an
/// element of a more specific atomic type is not a valid derivation and is
/// rejected; a genuinely derived (restriction) substitute, or a list/union under
/// an `anySimpleType` declaration, is still accepted.
@Suite("list/union xsi:type derivation")
struct SchemaListUnionXsiTypeTests {
    private func schema(declaredType: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="e" type="\(declaredType)"/>
          <xs:simpleType name="myList"><xs:list itemType="xs:int"/></xs:simpleType>
          <xs:simpleType name="myUnion"><xs:union memberTypes="xs:int xs:string"/></xs:simpleType>
          <xs:simpleType name="myInt"><xs:restriction base="xs:int"><xs:minInclusive value="0"/></xs:restriction></xs:simpleType>
        </xs:schema>
        """)
    }

    private func doc(_ type: String, _ value: String) -> String {
        #"<e xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="\#(type)">\#(value)</e>"#
    }

    @Test("a list or union xsi:type on an int-declared element is rejected")
    func test_listUnionOnAtomicRejected() throws {
        #expect(try !schema(declaredType: "xs:int").validate(doc("myList", "1 2")).isEmpty)
        #expect(try !schema(declaredType: "xs:int").validate(doc("myUnion", "x")).isEmpty)
    }

    @Test("a valid restriction xsi:type on an int-declared element is accepted")
    func test_restrictionAccepted() throws {
        #expect(try schema(declaredType: "xs:int").validate(doc("myInt", "5")).isEmpty)
    }

    @Test("a list or union xsi:type under anySimpleType is accepted")
    func test_listUnionUnderUrTypeAccepted() throws {
        #expect(try schema(declaredType: "xs:anySimpleType").validate(doc("myList", "1 2")).isEmpty)
        #expect(try schema(declaredType: "xs:anySimpleType").validate(doc("myUnion", "x")).isEmpty)
    }
}
