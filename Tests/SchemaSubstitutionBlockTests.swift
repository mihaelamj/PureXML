@testable import PureXML
import Testing

/// `block="substitution"` on a substitution-group head forbids any member from
/// standing in for it, regardless of the member's type derivation (#147, XSTS
/// disallowedSubst set). Only type-derivation blocks (`extension`/`restriction`)
/// had been applied, so a same-type member still substituted under a
/// substitution block.
@Suite("Substitution-group block")
struct SchemaSubstitutionBlockTests {
    private func schema(headBlock: String) throws -> PureXML.Schema.Document {
        let attribute = headBlock.isEmpty ? "" : " block=\"\(headBlock)\""
        return try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns="urn:s" targetNamespace="urn:s" elementFormDefault="qualified">
          <xs:element name="root">
            <xs:complexType><xs:sequence>
              <xs:element ref="Head" maxOccurs="unbounded"/>
            </xs:sequence></xs:complexType>
          </xs:element>
          <xs:element name="Head" type="T"\(attribute)/>
          <xs:complexType name="T"><xs:sequence><xs:element name="x" type="xs:string"/></xs:sequence></xs:complexType>
          <xs:element name="Member" type="T" substitutionGroup="Head"/>
        </xs:schema>
        """)
    }

    private let withMember = #"<root xmlns="urn:s"><Head><x>a</x></Head><Member><x>b</x></Member></root>"#
    private let headsOnly = #"<root xmlns="urn:s"><Head><x>a</x></Head><Head><x>b</x></Head></root>"#

    @Test("block='substitution' on the head rejects a substituting member")
    func test_substitutionBlocked() throws {
        #expect(try !schema(headBlock: "substitution").validate(withMember).isEmpty)
        // Plain heads are still fine.
        #expect(try schema(headBlock: "substitution").validate(headsOnly).isEmpty)
    }

    @Test("without a substitution block the member may substitute")
    func test_memberAllowedWithoutBlock() throws {
        #expect(try schema(headBlock: "").validate(withMember).isEmpty)
    }

    /// block="substitution" bars members even when the head is an ABSTRACT, UNTYPED
    /// element (the substitution block is type-independent). Previously the filter was
    /// skipped for a head with no type, so a member still substituted (particlesDc).
    @Test("block='substitution' on an untyped abstract head bars members")
    func test_substitutionBlockedOnUntypedAbstractHead() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns="urn:s" targetNamespace="urn:s" elementFormDefault="qualified">
          <xs:element name="doc"><xs:complexType><xs:sequence><xs:element ref="h"/></xs:sequence></xs:complexType></xs:element>
          <xs:element name="h" abstract="true" block="substitution"/>
          <xs:element name="m" substitutionGroup="h"/>
        </xs:schema>
        """)
        // A member substituting the substitution-blocked head is invalid.
        #expect(try !schema.validate(#"<doc xmlns="urn:s"><m/></doc>"#).isEmpty)
    }

    /// cvc-elt.4.3.2.1: an xsi:type naming a complex type must be derived from the
    /// element's declared type. A complex type on a different branch of the
    /// hierarchy is rejected; the declared type itself is valid.
    @Test("an xsi:type must be derived from the element's declared type")
    func test_xsiTypeMustDeriveFromDeclared() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns="urn:s" targetNamespace="urn:s" elementFormDefault="qualified">
          <xs:complexType name="B"><xs:sequence><xs:element name="f" type="xs:string"/></xs:sequence></xs:complexType>
          <xs:complexType name="De"><xs:complexContent><xs:extension base="B"/></xs:complexContent></xs:complexType>
          <xs:complexType name="Dr"><xs:complexContent><xs:restriction base="B">
            <xs:sequence><xs:element name="f" type="xs:string"/></xs:sequence>
          </xs:restriction></xs:complexContent></xs:complexType>
          <xs:element name="e" type="De"/>
        </xs:schema>
        """)
        func doc(_ type: String) -> String {
            #"<e xmlns="urn:s" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="\#(type)"><f>x</f></e>"#
        }
        // Dr (restriction of B) is on a different branch, not derived from De: invalid.
        #expect(try !schema.validate(doc("Dr")).isEmpty)
        // The declared type itself is valid.
        #expect(try schema.validate(doc("De")).isEmpty)
    }
}
