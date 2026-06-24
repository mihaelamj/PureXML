import Testing
@testable import PureXML

/// cvc-elt.4.3 with cos-st-derived-OK clause 2.2.4: an `xsi:type` is validly
/// derived from a union declared type when it is validly derived from one of the
/// union's member types. The `{disallowed substitutions}` (`block`) applies to
/// the derivation method used to reach that member, so a substitute that reaches
/// the declared union through a member by a blocked method must be rejected, even
/// though the substitute is not on the union's own base chain.
///
/// The W3C XSTS instance test `elemT074` is exactly this shape: `block="restriction"`
/// on the element, declared type a union, and an `xsi:type` that restricts a union
/// member. Before the union-member derivation path was followed, the substitution
/// was accepted (a false negative); the block check found no base-chain path to the
/// union and stayed silent.
@Suite("xsi:type block through a union member")
struct SchemaXSITypeUnionMemberBlockTests {
    /// `Member` restricts `A`; `A` is a member of the union `U`. The element
    /// `e` is declared with the union type and `block` set to `elementBlock`.
    private func schema(elementBlock: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root"><xs:complexType><xs:sequence>
            <xs:element ref="e"/>
          </xs:sequence></xs:complexType></xs:element>
          <xs:element name="e" type="U" block="\(elementBlock)"/>
          <xs:simpleType name="A">
            <xs:restriction base="xs:int"><xs:minInclusive value="0"/></xs:restriction>
          </xs:simpleType>
          <xs:simpleType name="B">
            <xs:restriction base="xs:string"/>
          </xs:simpleType>
          <xs:simpleType name="U"><xs:union memberTypes="A B"/></xs:simpleType>
          <xs:simpleType name="Member">
            <xs:restriction base="A"><xs:enumeration value="1"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """)
    }

    private let instance = #"<root><e xsi:type="Member" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">1</e></root>"#

    @Test("block='restriction' bars an xsi:type that restricts a union member")
    func test_blockBarsRestrictionThroughMember() throws {
        let errors = try schema(elementBlock: "restriction").validate(instance)
        #expect(!errors.isEmpty, "the substitution reaches union member A by restriction, which is blocked")
    }

    @Test("block='#all' bars it too")
    func test_blockAllBarsThroughMember() throws {
        #expect(try !schema(elementBlock: "#all").validate(instance).isEmpty)
    }

    @Test("block='extension' does NOT bar a restriction-derived member (no false positive)")
    func test_extensionBlockDoesNotBar() throws {
        // The derivation through the member uses restriction, not extension, so an
        // extension-only block leaves the valid substitution accepted.
        let errors = try schema(elementBlock: "extension").validate(instance)
        #expect(errors.isEmpty, "extension block must not reject a restriction-derived substitution")
    }

    @Test("no block accepts the substitution (no false positive)")
    func test_noBlockAccepts() throws {
        let errors = try schema(elementBlock: "").validate(instance)
        #expect(errors.isEmpty, "with no block the union-member substitution is valid")
    }

    /// A substitute that IS a union member must be accepted even when it also
    /// derives, by a blocked method, from another member listed before it: the
    /// union member clause is existential (cos-st-derived-OK 2.2.4), and the
    /// self-membership path uses no derivation method, so it is never blocked.
    /// Regression for an over-rejection where the first derivable member shadowed
    /// the later self-membership match.
    @Test("a member that also descends from an earlier member is accepted (no false positive)")
    func test_selfMembershipNotShadowedByEarlierMember() throws {
        // U's members are P then Q, and Q restricts P. xsi:type="Q" is a member of
        // U (valid), though it also reaches member P by the blocked restriction.
        let document = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root"><xs:complexType><xs:sequence>
            <xs:element ref="e"/>
          </xs:sequence></xs:complexType></xs:element>
          <xs:element name="e" type="U" block="restriction"/>
          <xs:simpleType name="P">
            <xs:restriction base="xs:int"><xs:minInclusive value="0"/></xs:restriction>
          </xs:simpleType>
          <xs:simpleType name="Q">
            <xs:restriction base="P"><xs:enumeration value="1"/></xs:restriction>
          </xs:simpleType>
          <xs:simpleType name="U"><xs:union memberTypes="P Q"/></xs:simpleType>
        </xs:schema>
        """)
        let instance = #"<root><e xsi:type="Q" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">1</e></root>"#
        #expect(try document.validate(instance).isEmpty, "Q is a member of U; self-membership uses no method and is not blocked")
    }
}
