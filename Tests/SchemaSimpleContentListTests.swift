import Testing
@testable import PureXML

/// A complex type whose `simpleContent` derives from a list or union simple type
/// keeps that variety, so its element content is validated as a list/union rather
/// than collapsing to an atomic value space. A `simpleContent` extension of a
/// list-of-int validates its text as a list of ints: a non-int item is rejected.
@Suite("simpleContent list/union variety")
struct SchemaSimpleContentListTests {
    private func schema() throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="ints"><xs:list itemType="xs:int"/></xs:simpleType>
          <xs:complexType name="CT"><xs:simpleContent>
            <xs:extension base="ints"><xs:attribute name="a" type="xs:string"/></xs:extension>
          </xs:simpleContent></xs:complexType>
          <xs:element name="e" type="CT"/>
        </xs:schema>
        """)
    }

    @Test("a valid int-list simpleContent is accepted")
    func test_validListAccepted() throws {
        #expect(try schema().validate(#"<e a="x">1 2 3</e>"#).isEmpty)
    }

    @Test("a non-int item in a list simpleContent is rejected")
    func test_invalidListItemRejected() throws {
        #expect(try !schema().validate(#"<e a="x">1 z 3</e>"#).isEmpty)
    }
}
