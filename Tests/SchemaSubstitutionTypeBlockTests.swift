import Testing
@testable import PureXML

/// A `block` on a substitution-group head's TYPE (its `{prohibited substitutions}`),
/// not only on the head element, bars a member whose type reaches the head's type
/// by the blocked derivation method. The substitution-group filter unions the head
/// element's `{disallowed substitutions}` with the head type's `{prohibited
/// substitutions}` (W3C sun disallowedSubst set).
@Suite("Substitution-group type block")
struct SchemaSubstitutionTypeBlockTests {
    private func schema(typeBlock: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns="urn:s" targetNamespace="urn:s"
                   elementFormDefault="qualified">
          <xs:element name="root"><xs:complexType><xs:sequence>
            <xs:element ref="Head"/>
          </xs:sequence></xs:complexType></xs:element>
          <xs:complexType name="Type" block="\(typeBlock)"><xs:sequence/></xs:complexType>
          <xs:element name="Head" type="Type"/>
          <xs:complexType name="Sub"><xs:complexContent><xs:restriction base="Type">
            <xs:sequence/>
          </xs:restriction></xs:complexContent></xs:complexType>
          <xs:element name="Member" type="Sub" substitutionGroup="Head"/>
        </xs:schema>
        """)
    }

    private let withMember = #"<root xmlns="urn:s"><Member/></root>"#
    private let withHead = #"<root xmlns="urn:s"><Head/></root>"#

    @Test("a type block='restriction' on the head's type bars a restriction member")
    func test_typeBlockBarsRestrictionMember() throws {
        // Member's type restricts Type, which blocks restriction: the substitution is barred.
        #expect(try !schema(typeBlock: "restriction").validate(withMember).isEmpty)
        // The head itself still validates.
        #expect(try schema(typeBlock: "restriction").validate(withHead).isEmpty)
    }

    @Test("a type block='extension' does not bar a restriction member")
    func test_typeBlockOtherMethodAllowsMember() throws {
        // Member derives by restriction; an extension-only block does not bar it.
        #expect(try schema(typeBlock: "extension").validate(withMember).isEmpty)
    }
}
