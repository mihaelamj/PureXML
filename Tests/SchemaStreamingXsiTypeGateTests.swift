import Testing
@testable import PureXML

/// The streaming validator must run the same `xsi:type` substitution-validity gate
/// (cvc-elt.4.3) the tree path runs, so it rejects a blocked, abstract, or
/// not-validly-derived override identically (#186). Each case asserts streaming
/// agrees with the tree oracle and that the invalid override is rejected, and a
/// valid override is accepted on both paths.
@Suite("XSD streaming xsi:type substitution gate (#186)")
struct SchemaStreamingXsiTypeGateTests {
    private let schema = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
      <xs:complexType name="Base"><xs:sequence><xs:element name="x" type="xs:string"/></xs:sequence></xs:complexType>
      <xs:complexType name="Derived">
        <xs:complexContent><xs:extension base="t:Base"><xs:sequence><xs:element name="z" type="xs:string"/></xs:sequence></xs:extension></xs:complexContent>
      </xs:complexType>
      <xs:complexType name="Abs" abstract="true">
        <xs:complexContent><xs:extension base="t:Base"><xs:sequence><xs:element name="z" type="xs:string"/></xs:sequence></xs:extension></xs:complexContent>
      </xs:complexType>
      <xs:complexType name="Unrelated"><xs:sequence><xs:element name="w" type="xs:string"/></xs:sequence></xs:complexType>
      <xs:complexType name="Blocked" block="#all"><xs:sequence><xs:element name="x" type="xs:string"/></xs:sequence></xs:complexType>
      <xs:complexType name="BlockedDerived">
        <xs:complexContent><xs:extension base="t:Blocked"><xs:sequence><xs:element name="z" type="xs:string"/></xs:sequence></xs:extension></xs:complexContent>
      </xs:complexType>
      <xs:element name="e" type="t:Base"/>
      <xs:element name="b" type="t:Blocked"/>
      <xs:element name="a" type="t:Abs"/>
    </xs:schema>
    """

    private func agreement(_ instance: String) throws -> [String] {
        let document = try PureXML.Schema.Document(schema)
        let tree = try document.validate(instance).map(\.reason).sorted()
        let streamed = try document.validate(streaming: instance).map(\.reason).sorted()
        #expect(tree == streamed, "streaming disagreed with tree on:\n\(instance)\n  tree: \(tree)\n  stream: \(streamed)")
        return streamed
    }

    private func instance(_ element: String, _ type: String, _ body: String) -> String {
        """
        <t:\(element) xmlns:t="urn:t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:type="t:\(type)">\(body)</t:\(element)>
        """
    }

    @Test("a valid derived xsi:type is accepted on both paths")
    func test_validOverrideAccepted() throws {
        #expect(try agreement(instance("e", "Derived", "<x>a</x><z>b</z>")).isEmpty)
    }

    @Test("a not-validly-derived xsi:type is rejected on both paths (cvc-elt.4.3.2.1)")
    func test_notDerivedRejected() throws {
        #expect(try !agreement(instance("e", "Unrelated", "<w>a</w>")).isEmpty)
    }

    @Test("an abstract xsi:type is rejected on both paths")
    func test_abstractRejected() throws {
        #expect(try !agreement(instance("e", "Abs", "<x>a</x><z>b</z>")).isEmpty)
    }

    @Test("a blocked xsi:type substitution is rejected on both paths")
    func test_blockedRejected() throws {
        #expect(try !agreement(instance("b", "BlockedDerived", "<x>a</x><z>b</z>")).isEmpty)
    }

    @Test("an abstract declared type with no xsi:type is rejected on both paths (cvc-elt.4.2)")
    func test_abstractDeclaredTypeRequiresXsiType() throws {
        let noOverride = """
        <t:a xmlns:t="urn:t"><x>a</x></t:a>
        """
        #expect(try !agreement(noOverride).isEmpty)
    }

    @Test("a root with no global declaration but a valid xsi:type is accepted on both paths")
    func test_undeclaredRootWithXsiTypeAccepted() throws {
        // The root 'undeclared' has no global element declaration; its xsi:type names a
        // known type, so both paths validate the body against that type (Sun target-NS
        // tests). Streaming must not report a false "no element declaration".
        #expect(try agreement(instance("undeclared", "Base", "<x>a</x>")).isEmpty)
    }

    @Test("an undeclared root with xsi:type and a wrong body is rejected with the same content error")
    func test_undeclaredRootWithXsiTypeWrongBody() throws {
        // Both paths must report the content-model error against the xsi:type, not a
        // root "no element declaration".
        let errors = try agreement(instance("undeclared", "Base", "<wrong>a</wrong>"))
        #expect(!errors.isEmpty)
        #expect(!errors.contains { $0.contains("no element declaration") }, "got: \(errors)")
    }

    @Test("a foreign-namespace root sharing a local name with a target-ns element uses its xsi:type, not that element")
    func test_foreignNamespaceRootDoesNotBindLocalNameElement() throws {
        // 'e' is a target-ns element typed t:Base. The root here is o:e in urn:other:
        // it has no global declaration, so its xsi:type='t:Unrelated' (a sibling type
        // not derived from Base) names the validating type. The bare-local-name root
        // fallback must NOT bind the target-ns 'e' across namespaces (that would gate
        // the body against Base and falsely reject the valid Unrelated override).
        let valid = """
        <o:e xmlns:o="urn:other" xmlns:t="urn:t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:type="t:Unrelated"><w>a</w></o:e>
        """
        #expect(try agreement(valid).isEmpty)
    }

    @Test("a strict-wildcard child typed only by its xsi:type is accepted on both paths")
    func test_strictWildcardChildTypedByXsiType() throws {
        // 'item' (urn:o) has no global declaration; a strict ##other wildcard admits it
        // and its xsi:type names a known type, so both paths validate it against that
        // type rather than reporting "no declaration for wildcard-matched element".
        let wildcardSchema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:complexType name="Thing"><xs:sequence><xs:element name="x" type="xs:string"/></xs:sequence></xs:complexType>
          <xs:element name="root">
            <xs:complexType><xs:sequence><xs:any namespace="##other" processContents="strict"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let xml = """
        <t:root xmlns:t="urn:t" xmlns:o="urn:o" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <o:item xsi:type="t:Thing"><x>hello</x></o:item>
        </t:root>
        """
        let document = try PureXML.Schema.Document(wildcardSchema)
        let tree = try document.validate(xml).map(\.reason).sorted()
        let streamed = try document.validate(streaming: xml).map(\.reason).sorted()
        #expect(tree == streamed, "tree: \(tree)\nstream: \(streamed)")
        #expect(streamed.isEmpty, "streaming rejected a valid wildcard-xsi:type child: \(streamed)")
    }
}
