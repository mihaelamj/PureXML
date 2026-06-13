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
}
