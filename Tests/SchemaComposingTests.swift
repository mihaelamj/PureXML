import Testing
@testable import PureXML

/// `Document(composing:)` pools several schema documents that jointly form one
/// schema into a single union, so cross-document facts (substitution-group
/// membership above all) are global, which a per-document merge cannot do (#161).
/// This path was previously exercised only by the opt-in XSTS harness; these give
/// it standing coverage (Sources/Schema/XSDParserUnion.swift).
@Suite("Schema Document(composing:) union")
struct SchemaComposingTests {
    /// Doc A: an abstract head plus a root whose content references it.
    private let docA = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:x" xmlns:x="urn:x">
      <xs:element name="head" abstract="true" type="xs:string"/>
      <xs:element name="root">
        <xs:complexType><xs:sequence>
          <xs:element ref="x:head" maxOccurs="unbounded"/>
        </xs:sequence></xs:complexType>
      </xs:element>
    </xs:schema>
    """
    /// Doc B (same target namespace, no import): a substitution-group member of head.
    private let docB = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:x" xmlns:x="urn:x">
      <xs:element name="member" substitutionGroup="x:head" type="xs:string"/>
    </xs:schema>
    """

    @Test("a cross-document substitution-group member validates when composed")
    func test_composedSubstitutionGroupResolves() throws {
        let schema = try PureXML.Schema.Document(composing: [docA, docB])
        // `member` (declared in B) substitutes the abstract `head` (declared in A):
        // valid only because composing makes the substitution group global.
        #expect(try schema.validate("<x:root xmlns:x='urn:x'><x:member>v</x:member></x:root>").isEmpty)
        // The abstract head itself may not appear directly.
        #expect(try !schema.validate("<x:root xmlns:x='urn:x'><x:head>v</x:head></x:root>").isEmpty)
        // An undeclared element is not a valid substitute.
        #expect(try !schema.validate("<x:root xmlns:x='urn:x'><x:other>v</x:other></x:root>").isEmpty)
    }

    @Test("composing a single document behaves like a plain compile")
    func test_composeSingleDocument() throws {
        let schema = try PureXML.Schema.Document(composing: [docA, docB])
        // Multiple members would also be admitted (maxOccurs unbounded).
        #expect(try schema.validate("<x:root xmlns:x='urn:x'><x:member>a</x:member><x:member>b</x:member></x:root>").isEmpty)
    }
}
