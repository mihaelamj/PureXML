import Testing
@testable import PureXML

/// Schema-driven completions: the exact follow-set of allowed next elements,
/// whether content may end, and attribute required/present status. The basis for
/// editor autocomplete and "what's missing".
@Suite("XSD completions")
struct XSDCompletionTests2 {
    private let xsd = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="order">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="name" type="xs:string"/>
            <xs:element name="qty" type="xs:integer"/>
            <xs:element name="note" type="xs:string" minOccurs="0"/>
          </xs:sequence>
          <xs:attribute name="id" type="xs:string" use="required"/>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    private func completions(_ xml: String) throws -> PureXML.Schema.Completions? {
        let schema = try PureXML.Schema.Document(xsd)
        let (tree, _) = PureXML.readTree(xml)
        return schema.completions(at: [.element("order")], in: tree)
    }

    @Test("The follow-set is the exact next allowed element")
    func test_followSet() throws {
        #expect(try completions("<order id='1'></order>")?.elements == ["name"])
        #expect(try completions("<order><name>n</name></order>")?.elements == ["qty"])
        #expect(try completions("<order><name>n</name><qty>1</qty></order>")?.elements == ["note"])
    }

    @Test("complete reflects whether a required child is still expected")
    func test_complete() throws {
        #expect(try completions("<order><name>n</name></order>")?.complete == false)
        #expect(try completions("<order><name>n</name><qty>1</qty></order>")?.complete == true)
    }

    @Test("Attribute completions carry required and present status")
    func test_attributes() throws {
        let attrs = try #require(try completions("<order></order>")?.attributes)
        #expect(attrs == [.init(name: "id", required: true, present: false)])
        let present = try #require(try completions("<order id='1'></order>")?.attributes)
        #expect(present == [.init(name: "id", required: true, present: true)])
    }

    @Test("Completions resolve for a nested element by its coding path")
    func test_nested() throws {
        let nestedXsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root">
            <xs:complexType><xs:sequence>
              <xs:element name="item">
                <xs:complexType><xs:sequence>
                  <xs:element name="a" type="xs:string"/>
                </xs:sequence></xs:complexType>
              </xs:element>
            </xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let schema = try PureXML.Schema.Document(nestedXsd)
        let (tree, _) = PureXML.readTree("<root><item></item></root>")
        let here = schema.completions(at: [.element("root"), .element("item")], in: tree)
        #expect(here?.elements == ["a"])
        #expect(here?.complete == false)
    }
}
