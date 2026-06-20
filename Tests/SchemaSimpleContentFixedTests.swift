import Testing
@testable import PureXML

/// A `fixed` value on an element whose type is a complex type with `simpleContent`
/// must be compared in the simple type's value space (cvc-elt.5.2.2.1), not as a raw
/// string (#202). Both the tree and streaming paths must agree, so "05" satisfies an
/// xs:int `fixed="5"` and is not falsely rejected.
@Suite("XSD simpleContent fixed value-space (#202)")
struct SchemaSimpleContentFixedTests {
    private let schema = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
      <xs:element name="r" type="t:R" fixed="5"/>
      <xs:complexType name="R">
        <xs:simpleContent>
          <xs:extension base="xs:int"><xs:attribute name="u" type="xs:string"/></xs:extension>
        </xs:simpleContent>
      </xs:complexType>
    </xs:schema>
    """

    private func agreement(_ instance: String) throws -> [String] {
        let document = try PureXML.Schema.Document(schema)
        let tree = try document.validate(instance).map(\.reason).sorted()
        let streamed = try document.validate(streaming: instance).map(\.reason).sorted()
        #expect(tree == streamed, "streaming disagreed with tree:\n  tree: \(tree)\n  stream: \(streamed)")
        return streamed
    }

    @Test("a value-space-equal fixed simpleContent value is accepted on both paths")
    func test_valueSpaceEqualAccepted() throws {
        #expect(try agreement("<t:r xmlns:t=\"urn:t\" u=\"x\">05</t:r>").isEmpty)
    }

    @Test("a value-space-different fixed simpleContent value is rejected on both paths")
    func test_valueSpaceDifferentRejected() throws {
        #expect(try !agreement("<t:r xmlns:t=\"urn:t\" u=\"x\">6</t:r>").isEmpty)
    }
}
