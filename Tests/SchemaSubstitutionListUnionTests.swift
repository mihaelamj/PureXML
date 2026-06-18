@testable import PureXML
import Testing

/// A substitution-group member whose type is a list or union derives only from
/// `anySimpleType`, so it may affiliate only to a head typed `anySimpleType` (or
/// to the same type, or as a recorded restriction of the head's type). Affiliating
/// a list/union-typed member to an unrelated head type is an invalid schema
/// (W3C addB141 / test82919).
@Suite("substitution-group list/union member type")
struct SchemaSubstitutionListUnionTests {
    @Test("a union member of a list-typed head is rejected at compile")
    func test_unionMemberOfListHeadRejected() throws {
        #expect(throws: (any Error).self) {
            try PureXML.Schema.Document("""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:simpleType name="L"><xs:list itemType="xs:int"/></xs:simpleType>
              <xs:simpleType name="U"><xs:union memberTypes="L xs:date"/></xs:simpleType>
              <xs:element name="e1" type="L"/>
              <xs:element name="e2" type="U" substitutionGroup="e1"/>
            </xs:schema>
            """)
        }
    }

    @Test("a list/union member of an anySimpleType head, and a restriction of a list head, compile")
    func test_validListUnionAffiliationsAccepted() throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="L"><xs:list itemType="xs:int"/></xs:simpleType>
          <xs:element name="h" type="xs:anySimpleType"/>
          <xs:element name="m" type="L" substitutionGroup="h"/>
        </xs:schema>
        """)
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="L"><xs:list itemType="xs:int"/></xs:simpleType>
          <xs:simpleType name="LR"><xs:restriction base="L"><xs:length value="2"/></xs:restriction></xs:simpleType>
          <xs:element name="h" type="L"/>
          <xs:element name="m" type="LR" substitutionGroup="h"/>
        </xs:schema>
        """)
    }
}
