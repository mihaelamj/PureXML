import Testing
@testable import PureXML

/// An empty element with a `default`/`fixed` value constraint takes that value as
/// its content, and that value (not the empty string) must satisfy the element's
/// simple type (cvc-elt.5.1.2 / cvc-elt.5.2.2.2). The streaming validator must apply
/// the constraint the same way the tree path does (#200), so an empty element with a
/// valid default is not falsely rejected. Each case asserts streaming agrees with
/// the tree-path oracle.
@Suite("XSD streaming default/fixed value constraints (#200)")
struct SchemaStreamingValueConstraintTests {
    private func schema(_ constraint: String) -> String {
        """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:complexType name="T"><xs:sequence>
            <xs:element name="a" type="xs:int" \(constraint)/>
          </xs:sequence></xs:complexType>
          <xs:element name="r" type="t:T"/>
        </xs:schema>
        """
    }

    private func agreement(_ schemaSource: String, _ instance: String) throws -> [String] {
        let document = try PureXML.Schema.Document(schemaSource)
        let tree = try document.validate(instance).map(\.reason).sorted()
        let streamed = try document.validate(streaming: instance).map(\.reason).sorted()
        #expect(tree == streamed, "streaming disagreed with tree:\n  tree: \(tree)\n  stream: \(streamed)")
        return streamed
    }

    @Test("an empty element with a valid default is accepted on both paths")
    func test_emptyTakesDefault() throws {
        let instance = "<t:r xmlns:t=\"urn:t\"><a></a></t:r>"
        #expect(try agreement(schema("default=\"5\""), instance).isEmpty)
    }

    @Test("an empty element with a valid fixed value is accepted on both paths")
    func test_emptyTakesFixed() throws {
        let instance = "<t:r xmlns:t=\"urn:t\"><a></a></t:r>"
        #expect(try agreement(schema("fixed=\"5\""), instance).isEmpty)
    }

    @Test("a present non-empty value is still validated against the type on both paths")
    func test_presentValueStillValidated() throws {
        let instance = "<t:r xmlns:t=\"urn:t\"><a>notanint</a></t:r>"
        #expect(try !agreement(schema("default=\"5\""), instance).isEmpty)
    }

    @Test("same-local-name elements with different defaults use the matched particle, not the flat map")
    func test_collidingLocalNameConstraints() throws {
        // Two complex types both declare a local element 'v' with a different default;
        // B is declared after A, so the by-local-name elementConstraints map keeps B's
        // (type-invalid for A). Streaming must use A's matched-particle default "5" for
        // an empty <v/> under root (type A), not the colliding "hello".
        let collisionSchema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:element name="root" type="t:A"/>
          <xs:complexType name="A"><xs:sequence>
            <xs:element name="v" type="xs:int" default="5"/>
          </xs:sequence></xs:complexType>
          <xs:element name="other" type="t:B"/>
          <xs:complexType name="B"><xs:sequence>
            <xs:element name="v" type="xs:string" default="hello"/>
          </xs:sequence></xs:complexType>
        </xs:schema>
        """
        let instance = "<t:root xmlns:t=\"urn:t\"><v/></t:root>"
        #expect(try agreement(collisionSchema, instance).isEmpty)
    }

    @Test("a present fixed value is compared in the type's value space, not raw string")
    func test_fixedValueSpaceComparison() throws {
        // "05" equals fixed "5" in the xs:int value space; both paths accept.
        let instance = "<t:r xmlns:t=\"urn:t\"><a>05</a></t:r>"
        #expect(try agreement(schema("fixed=\"5\""), instance).isEmpty)
    }

    @Test("a present fixed value that differs in value space is rejected on both paths")
    func test_fixedValueMismatchRejected() throws {
        let instance = "<t:r xmlns:t=\"urn:t\"><a>6</a></t:r>"
        #expect(try !agreement(schema("fixed=\"5\""), instance).isEmpty)
    }

    @Test("a present fixed value under a same-local-name collision uses the matched particle")
    func test_fixedCollisionPresentContent() throws {
        let collisionSchema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:element name="root" type="t:A"/>
          <xs:complexType name="A"><xs:sequence>
            <xs:element name="v" type="xs:int" fixed="5"/>
          </xs:sequence></xs:complexType>
          <xs:element name="other" type="t:B"/>
          <xs:complexType name="B"><xs:sequence>
            <xs:element name="v" type="xs:string" fixed="hello"/>
          </xs:sequence></xs:complexType>
        </xs:schema>
        """
        // <v>5</v> under root (type A) matches A's fixed "5", not B's colliding "hello".
        let instance = "<t:root xmlns:t=\"urn:t\"><v>5</v></t:root>"
        #expect(try agreement(collisionSchema, instance).isEmpty)
    }
}
