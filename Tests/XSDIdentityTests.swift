@testable import PureXML
import Testing

@Suite("XSD identity constraints")
struct XSDIdentityTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    private let head = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"

    @Test("xs:unique rejects a duplicated field value")
    func test_unique() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" type="xs:string" maxOccurs="unbounded"/></xs:sequence>
            </xs:complexType>
            <xs:unique name="byId">
              <xs:selector xpath="item"/>
              <xs:field xpath="@id"/>
            </xs:unique>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<list><item id=\"1\"/><item id=\"2\"/></list>").isEmpty)
        #expect(try !validate(xsd, "<list><item id=\"1\"/><item id=\"1\"/></list>").isEmpty)
        // unique tolerates a missing field
        #expect(try validate(xsd, "<list><item/><item/></list>").isEmpty)
    }

    @Test("xs:key requires every field to be present and distinct")
    func test_key() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" type="xs:string" maxOccurs="unbounded"/></xs:sequence>
            </xs:complexType>
            <xs:key name="itemKey">
              <xs:selector xpath="item"/>
              <xs:field xpath="@id"/>
            </xs:key>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<list><item id=\"1\"/><item id=\"2\"/></list>").isEmpty)
        #expect(try !validate(xsd, "<list><item id=\"1\"/><item id=\"1\"/></list>").isEmpty)
        // a key field may not be absent
        #expect(try !validate(xsd, "<list><item id=\"1\"/><item/></list>").isEmpty)
    }

    @Test("xs:keyref requires a matching key value")
    func test_keyref() throws {
        let xsd = """
        \(head)
          <xs:element name="orders">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="product" type="xs:string" maxOccurs="unbounded"/>
                <xs:element name="line" type="xs:string" maxOccurs="unbounded"/>
              </xs:sequence>
            </xs:complexType>
            <xs:key name="prodKey">
              <xs:selector xpath="product"/>
              <xs:field xpath="@code"/>
            </xs:key>
            <xs:keyref name="lineRef" refer="prodKey">
              <xs:selector xpath="line"/>
              <xs:field xpath="@product"/>
            </xs:keyref>
          </xs:element>
        </xs:schema>
        """
        let valid = "<orders><product code=\"A\"/><product code=\"B\"/><line product=\"A\"/></orders>"
        let dangling = "<orders><product code=\"A\"/><line product=\"Z\"/></orders>"
        #expect(try validate(xsd, valid).isEmpty)
        // The dangling keyref is located at the offending field @product.
        let failure = try #require(validate(xsd, dangling).first)
        #expect(failure.codingPath.map(\.stringValue) == ["orders", "line", "@product"])
        #expect(String(describing: failure).hasSuffix("at path: orders/line/@product"))
    }

    @Test("Identity-constraint errors are located at the offending field")
    func test_identityErrorsCarryPath() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" type="xs:string" maxOccurs="unbounded"/></xs:sequence>
            </xs:complexType>
            <xs:key name="itemKey">
              <xs:selector xpath="item"/>
              <xs:field xpath="@id"/>
            </xs:key>
          </xs:element>
        </xs:schema>
        """
        // The error locates the offending field (the duplicate item[2]'s @id),
        // not just the element that declares the key.
        let errors = try validate(xsd, "<list><item id=\"1\"/><item id=\"1\"/></list>")
        let failure = try #require(errors.first)
        #expect(failure.codingPath.map(\.stringValue) == ["list", "item", "@id"])
        #expect(String(describing: failure).hasSuffix("at path: list/item[2]/@id"))
    }

    @Test("A nested selector locates the offender at full depth with an intermediate index")
    func test_identityErrorDeepPath() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="group" maxOccurs="unbounded">
                  <xs:complexType>
                    <xs:sequence><xs:element name="item" type="xs:string" maxOccurs="unbounded"/></xs:sequence>
                  </xs:complexType>
                </xs:element>
              </xs:sequence>
            </xs:complexType>
            <xs:key name="k"><xs:selector xpath="group/item"/><xs:field xpath="@id"/></xs:key>
          </xs:element>
        </xs:schema>
        """
        // The duplicate id "1" appears in the second group, so the offender is
        // list/group[2]/item: a grandchild, with the index on the intermediate group.
        let xml = "<list><group><item id=\"1\"/></group><group><item id=\"1\"/></group></list>"
        let failure = try #require(validate(xsd, xml).first)
        #expect(failure.codingPath.map(\.stringValue) == ["list", "group", "item", "@id"])
        #expect(String(describing: failure).hasSuffix("at path: list/group[2]/item/@id"))
    }

    @Test("A keyref resolves against a key declared on an ancestor (cross-scope)")
    func test_keyrefCrossScope() throws {
        // pk is declared on <catalog>; the keyref is declared on the deeper
        // <orders>, so resolution must find the ancestor's key in scope.
        let xsd = """
        \(head)
          <xs:element name="catalog">
            <xs:complexType><xs:sequence>
              <xs:element name="products"><xs:complexType><xs:sequence>
                <xs:element name="product" maxOccurs="unbounded"><xs:complexType><xs:attribute name="code" type="xs:string"/></xs:complexType></xs:element>
              </xs:sequence></xs:complexType></xs:element>
              <xs:element name="orders"><xs:complexType><xs:sequence>
                <xs:element name="line" maxOccurs="unbounded"><xs:complexType><xs:attribute name="ref" type="xs:string"/></xs:complexType></xs:element>
              </xs:sequence></xs:complexType>
                <xs:keyref name="kr" refer="pk"><xs:selector xpath="line"/><xs:field xpath="@ref"/></xs:keyref>
              </xs:element>
            </xs:sequence></xs:complexType>
            <xs:key name="pk"><xs:selector xpath="products/product"/><xs:field xpath="@code"/></xs:key>
          </xs:element>
        </xs:schema>
        """
        let valid = "<catalog><products><product code=\"A\"/></products><orders><line ref=\"A\"/></orders></catalog>"
        let dangling = "<catalog><products><product code=\"A\"/></products><orders><line ref=\"Z\"/></orders></catalog>"
        #expect(try validate(xsd, valid).isEmpty)
        #expect(try validate(xsd, dangling).contains { $0.reason.contains("no matching key 'pk'") })
    }

    @Test("A malformed field XPath is a located error, not a silently disabled constraint")
    func test_malformedFieldReported() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" type="xs:string" maxOccurs="unbounded"/></xs:sequence>
            </xs:complexType>
            <xs:key name="k"><xs:selector xpath="item"/><xs:field xpath="@id["/></xs:key>
          </xs:element>
        </xs:schema>
        """
        let errors = try validate(xsd, "<list><item id=\"1\"/><item id=\"1\"/></list>")
        #expect(errors.contains { $0.reason.contains("invalid field XPath '@id['") }, "\(errors.map(\.reason))")
    }

    @Test("A malformed selector XPath is a located error")
    func test_malformedSelectorReported() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" type="xs:string" maxOccurs="unbounded"/></xs:sequence>
            </xs:complexType>
            <xs:key name="k"><xs:selector xpath="item["/><xs:field xpath="@id"/></xs:key>
          </xs:element>
        </xs:schema>
        """
        let errors = try validate(xsd, "<list><item id=\"1\"/></list>")
        #expect(errors.contains { $0.reason.contains("invalid selector XPath 'item['") }, "\(errors.map(\.reason))")
    }

    @Test("A child-element field locates the error at that child")
    func test_childElementField() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="item" maxOccurs="unbounded">
                  <xs:complexType><xs:sequence><xs:element name="code" type="xs:string"/></xs:sequence></xs:complexType>
                </xs:element>
              </xs:sequence>
            </xs:complexType>
            <xs:key name="k"><xs:selector xpath="item"/><xs:field xpath="code"/></xs:key>
          </xs:element>
        </xs:schema>
        """
        let xml = "<list><item><code>x</code></item><item><code>x</code></item></list>"
        let failure = try #require(validate(xsd, xml).first)
        #expect(String(describing: failure).hasSuffix("at path: list/item[2]/code"))
    }
}
