@testable import PureXML
import Testing

@Suite("Streaming XSD validation")
struct StreamingXSDTests {
    private let schema = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="order">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="id" type="xs:int"/>
            <xs:element name="item" maxOccurs="unbounded">
              <xs:complexType>
                <xs:sequence>
                  <xs:element name="name" type="xs:string"/>
                  <xs:element name="qty" type="xs:positiveInteger"/>
                </xs:sequence>
                <xs:attribute name="sku" type="xs:string" use="required"/>
              </xs:complexType>
            </xs:element>
          </xs:sequence>
          <xs:attribute name="ref" type="xs:string"/>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    /// Streaming validation must agree with the tree validator on the same
    /// document (these schemas carry no identity constraints, so the tree output
    /// is exactly the content/attribute errors streaming produces). Agreement on
    /// every document is the correctness proof.
    private func check(_ xml: String, expectValid: Bool) throws {
        let document = try PureXML.Schema.Document(schema)
        let tree = try document.validate(xml).map(\.reason).sorted()
        let streamed = try document.validate(streaming: xml).map(\.reason).sorted()
        #expect(tree == streamed, "streaming disagreed with tree on: \(xml)\n  tree: \(tree)\n  stream: \(streamed)")
        #expect(streamed.isEmpty == expectValid, "wrong verdict for: \(xml) -> \(streamed)")
    }

    @Test("Valid documents agree and pass")
    func test_valid() throws {
        try check("<order ref=\"r\"><id>1</id><item sku=\"a\"><name>x</name><qty>2</qty></item></order>", expectValid: true)
        // Repeated item (maxOccurs unbounded), optional ref omitted.
        try check(
            "<order><id>1</id><item sku=\"a\"><name>x</name><qty>2</qty></item>"
                + "<item sku=\"b\"><name>y</name><qty>9</qty></item></order>",
            expectValid: true,
        )
    }

    @Test("Invalid documents agree and fail")
    func test_invalid() throws {
        // Missing required attribute sku.
        try check("<order><id>1</id><item><name>x</name><qty>2</qty></item></order>", expectValid: false)
        // A bad xs:int value for id.
        try check("<order><id>notanint</id><item sku=\"a\"><name>x</name><qty>2</qty></item></order>", expectValid: false)
        // A bad xs:positiveInteger value for qty.
        try check("<order><id>1</id><item sku=\"a\"><name>x</name><qty>0</qty></item></order>", expectValid: false)
        // Missing required child qty.
        try check("<order><id>1</id><item sku=\"a\"><name>x</name></item></order>", expectValid: false)
        // Children out of order.
        try check("<order><id>1</id><item sku=\"a\"><qty>2</qty><name>x</name></item></order>", expectValid: false)
        // An undeclared extra child.
        try check("<order><id>1</id><item sku=\"a\"><name>x</name><qty>2</qty><extra/></item></order>", expectValid: false)
        // An undeclared attribute.
        try check("<order><id>1</id><item sku=\"a\" bogus=\"1\"><name>x</name><qty>2</qty></item></order>", expectValid: false)
        // No items at all (item is required, maxOccurs unbounded but minOccurs 1).
        try check("<order><id>1</id></order>", expectValid: false)
    }

    @Test("The streaming content check is a composable Validation value")
    func test_shallowValidityRule() {
        // The streaming content check applied directly through the Validation rule.
        let validator = PureXML.Schema.ComplexValidator()
        let rule = PureXML.Schema.ComplexValidator.shallowValidity
        #expect(rule.description == "Each streamed element is valid against its declared XSD type")
        // An empty-content element carrying a child element is invalid.
        let bad = PureXML.Schema.ResolvedElement(
            element: PureXML.Model.Element("v", children: [.element(.init("child"))]),
            type: .complex(PureXML.Schema.ComplexType(content: .empty)),
        )
        let errors = rule.apply(to: bad, at: [.element("v")], in: validator)
        #expect(errors.contains { $0.reason.contains("must be empty") })
        #expect(errors.first?.codingPath.map(\.stringValue) == ["v"])
    }
}
