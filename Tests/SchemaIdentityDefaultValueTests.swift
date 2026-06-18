import Testing
@testable import PureXML

/// An identity-constraint field that selects an absent attribute or an empty
/// element whose declaration carries a `default`/`fixed` takes that value as its
/// identity component, so two members can collide on the defaulted value
/// (idG011/idG012, idF016/idF017). A present attribute (even value "") and a
/// non-empty element are instance-supplied and never defaulted.
@Suite("Identity-constraint fields take a declared default or fixed value")
struct SchemaIdentityDefaultValueTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func errors(_ schema: String, _ instance: String) -> [PureXML.Validation.ValidationError] {
        guard let document = try? PureXML.Schema.Document("<xs:schema \(xsd)>\(schema)</xs:schema>") else {
            Issue.record("schema failed to compile")
            return []
        }
        return (try? document.validate(instance)) ?? []
    }

    /// An `@val` attribute with `default="test"`: one member omits it (takes the
    /// default), another carries `val="test"`, so the two keys collide.
    private func attributeSchema(_ constraint: String) -> String {
        """
        <xs:element name="root">
          <xs:complexType><xs:sequence>
            <xs:element ref="uid" maxOccurs="unbounded"/>
          </xs:sequence></xs:complexType>
          <xs:unique name="uuid">
            <xs:selector xpath=".//uid"/><xs:field xpath="@val"/>
          </xs:unique>
        </xs:element>
        <xs:element name="uid">
          <xs:complexType>
            <xs:attribute name="val" type="xs:string" \(constraint)/>
          </xs:complexType>
        </xs:element>
        """
    }

    @Test("Absent attribute with a default collides with the same explicit value")
    func test_defaultAttributeDuplicate() {
        let instance = "<root><uid val=\"test\"/><uid/></root>"
        #expect(!errors(attributeSchema("default=\"test\""), instance).isEmpty)
    }

    @Test("Absent attribute with a fixed value collides with the same explicit value")
    func test_fixedAttributeDuplicate() {
        let instance = "<root><uid val=\"test\"/><uid/></root>"
        #expect(!errors(attributeSchema("fixed=\"test\""), instance).isEmpty)
    }

    /// A `.` element-value field where one member is empty (takes the element's
    /// `default`) and another carries the same text, so the two keys collide.
    @Test("Empty element with a default collides with the same explicit value")
    func test_defaultElementDuplicate() {
        let schema = """
        <xs:element name="root">
          <xs:complexType><xs:sequence>
            <xs:element ref="uid" maxOccurs="unbounded"/>
          </xs:sequence></xs:complexType>
          <xs:unique name="uuid">
            <xs:selector xpath=".//uid"/><xs:field xpath="."/>
          </xs:unique>
        </xs:element>
        <xs:element name="uid" type="xs:string" default="test"/>
        """
        let instance = "<root><uid>test</uid><uid/></root>"
        #expect(!errors(schema, instance).isEmpty)
    }

    /// FP-GUARD: an attribute PRESENT with value "" and NO default is its own
    /// value, distinct from another member's "test", so the instance is valid.
    @Test("A present empty attribute is its own value, not a default")
    func test_presentEmptyAttributeNotDefaulted() {
        let instance = "<root><uid val=\"\"/><uid val=\"test\"/></root>"
        #expect(errors(attributeSchema(""), instance).isEmpty)
    }

    /// FP-GUARD: two genuinely distinct present values never collide, with or
    /// without a declared default.
    @Test("Two distinct present values are accepted")
    func test_distinctPresentValuesAccepted() {
        let instance = "<root><uid val=\"a\"/><uid val=\"b\"/></root>"
        #expect(errors(attributeSchema("default=\"test\""), instance).isEmpty)
    }
}
