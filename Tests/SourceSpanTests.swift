import Testing
@testable import PureXML

/// Source spans on the ranged tree, and the bridge that maps a validation
/// finding's coding path to a source range: the keystone for editor use.
@Suite("Source spans")
struct SourceSpanTests {
    @Test("Ranged read attaches a source span to each node")
    func test_spans() {
        let (tree, diagnostics) = PureXML.readTree("<order>\n  <qty>x</qty>\n</order>")
        #expect(diagnostics.isEmpty)
        let order = tree.children.first
        #expect(order?.sourceRange?.start.line == 1)
        #expect(order?.sourceRange?.start.column == 1)
        let qty = tree.node(at: [.element("order"), .element("qty")])
        #expect(qty?.value == "")
        #expect(qty?.sourceRange?.start == PureXML.Parsing.Mark(line: 2, column: 3, offset: 10))
    }

    @Test("A coding path resolves to its node, with a sibling index when repeated")
    func test_navigation() {
        let (tree, _) = PureXML.readTree("<r><i>a</i><i>b</i></r>")
        #expect(tree.node(at: [.element("r"), .element("i", index: 2)])?.children.first?.value == "b")
        #expect(tree.node(at: [.element("r"), .element("i")])?.children.first?.value == "a")
        #expect(tree.node(at: [.element("r"), .element("missing")]) == nil)
    }

    @Test("A validation finding maps to a source range through the ranged tree")
    func test_validationToRange() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="order">
            <xs:complexType>
              <xs:sequence><xs:element name="qty" type="xs:integer"/></xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let xml = "<order>\n  <qty>lots</qty>\n</order>"
        let errors = try PureXML.Schema.Document(xsd).validate(xml)
        #expect(errors.count == 1)

        // The editor flow: read a ranged tree, then resolve the finding's path to a span.
        let (tree, _) = PureXML.readTree(xml)
        let range = tree.sourceRange(at: errors[0].codingPath)
        #expect(range != nil)
        #expect(range?.start == PureXML.Parsing.Mark(line: 2, column: 3, offset: 10))
    }

    @Test("Ranged read of invalid input never crashes and still spans what parsed")
    func test_invalidRanged() {
        let (tree, diagnostics) = PureXML.readTree("<a><b>x")
        #expect(!diagnostics.isEmpty)
        let inner = tree.node(at: [.element("a"), .element("b")])
        #expect(inner?.sourceRange != nil)
    }
}
