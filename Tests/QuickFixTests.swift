@testable import PureXML
import Testing

/// Quick-fixes derived from the structured schema completions, with precise
/// placement from content spans. The strongest check: applying a fix yields XML
/// that the same schema then accepts.
@Suite("Quick fixes")
struct QuickFixTests {
    private let xsd = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="order">
        <xs:complexType>
          <xs:sequence><xs:element name="qty" type="xs:integer"/></xs:sequence>
          <xs:attribute name="id" type="xs:string" use="required"/>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    private func apply(_ edit: PureXML.TextEdit, to xml: String) -> String {
        var characters = Array(xml)
        let start = edit.range.start.offset
        let end = edit.range.end.offset
        characters.replaceSubrange(start ..< end, with: Array(edit.replacement))
        return String(characters)
    }

    @Test("A missing required attribute becomes an insertion before the start tag")
    func test_addAttribute() throws {
        let schema = try PureXML.Schema.Document(xsd)
        let (tree, _) = PureXML.readTree("<order><qty>1</qty></order>")
        let fixes = schema.quickFixes(at: [.element("order")], in: tree)
        let fix = try #require(fixes.first { $0.title.contains("attribute 'id'") })
        let fixed = apply(fix.edits[0], to: "<order><qty>1</qty></order>")
        #expect(fixed == "<order id=\"\"><qty>1</qty></order>")
        // The required-attribute error is gone after applying.
        #expect(try schema.validate(fixed).contains { $0.reason.contains("required attribute 'id'") } == false)
    }

    @Test("A still-expected required child becomes an insertion before the end tag")
    func test_insertChild() throws {
        let schema = try PureXML.Schema.Document(xsd)
        let (tree, _) = PureXML.readTree("<order id='1'></order>")
        let fixes = schema.quickFixes(at: [.element("order")], in: tree)
        let fix = try #require(fixes.first { $0.title == "Insert <qty>" })
        let fixed = apply(fix.edits[0], to: "<order id='1'></order>")
        #expect(fixed == "<order id='1'><qty></qty></order>")
    }

    @Test("A complete, valid element offers no fixes")
    func test_noFixes() throws {
        let schema = try PureXML.Schema.Document(xsd)
        let (tree, _) = PureXML.readTree("<order id='1'><qty>1</qty></order>")
        #expect(schema.quickFixes(at: [.element("order")], in: tree).isEmpty)
    }
}
