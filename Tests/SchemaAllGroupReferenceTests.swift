import Testing
@testable import PureXML

/// XSD 1.0 cos-all-limited (#158): a reference to a model group whose content is an
/// `all` group is itself an all-group particle, so its `maxOccurs` must be 1 (and
/// `minOccurs` 0 or 1). Mirrors corpus particlesEa025 (a group ref to an all group
/// with maxOccurs="2").
@Suite("XSD cos-all-limited group reference (#158)")
struct SchemaAllGroupReferenceTests {
    private func allGroupRef(maxOccurs: String) -> String {
        """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:group name="G"><xs:all><xs:element name="a1" type="xs:string"/><xs:element name="a2" type="xs:string"/></xs:all></xs:group>
          <xs:element name="doc"><xs:complexType><xs:group ref="t:G" maxOccurs="\(maxOccurs)"/></xs:complexType></xs:element>
        </xs:schema>
        """
    }

    private func compiles(_ schema: String) -> Bool {
        (try? PureXML.Schema.Document(schema)) != nil
    }

    @Test("a group reference to an all group with maxOccurs>1 is rejected (particlesEa025)")
    func test_allGroupRefMaxOccursTwoRejected() {
        #expect(!compiles(allGroupRef(maxOccurs: "2")))
    }

    @Test("a group reference to an all group with maxOccurs=1 is accepted")
    func test_allGroupRefMaxOccursOneAccepted() {
        #expect(compiles(allGroupRef(maxOccurs: "1")))
    }

    @Test("a group reference to a non-all (sequence) group with maxOccurs>1 is accepted")
    func test_sequenceGroupRefMaxOccursTwoAccepted() {
        let schema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:group name="G"><xs:sequence><xs:element name="a1" type="xs:string"/></xs:sequence></xs:group>
          <xs:element name="doc"><xs:complexType><xs:group ref="t:G" maxOccurs="2"/></xs:complexType></xs:element>
        </xs:schema>
        """
        #expect(compiles(schema))
    }
}
