import Testing
@testable import PureXML

/// `unique`/`key`/`keyref` detect duplicates through a raw-string `Set` fast path
/// for whitespace-preserving lexical fields (most ids) and an exact value-space
/// scan for the rest, so a wide list validates in linear time without changing
/// which documents pass. These pin that the fast path and the fallback agree:
/// raw-string duplicates are caught, value-space and whitespace-collapsing
/// duplicates that the fast path deliberately skips are still caught by the
/// fallback, and a colliding target keeps its positional error location.
@Suite("Identity-constraint duplicate detection across the fast path and fallback")
struct SchemaIdentityScaleDuplicateTests {
    private func uniqueSchema(field: String, type: String) throws -> PureXML.Schema.Document {
        let content = field == "@v"
            ? "<xsd:attribute name=\"v\" type=\"\(type)\"/>"
            : "<xsd:simpleContent><xsd:extension base=\"\(type)\"/></xsd:simpleContent>"
        return try PureXML.Schema.Document("""
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <xsd:element name="catalog">
            <xsd:complexType><xsd:sequence>
              <xsd:element name="item" maxOccurs="unbounded">
                <xsd:complexType>\(content)</xsd:complexType>
              </xsd:element>
            </xsd:sequence></xsd:complexType>
            <xsd:unique name="u"><xsd:selector xpath="item"/><xsd:field xpath="\(field)"/></xsd:unique>
          </xsd:element>
        </xsd:schema>
        """)
    }

    @Test("a wide list of distinct string ids passes; one repeat is caught")
    func test_rawFastPath() throws {
        let schema = try uniqueSchema(field: "@v", type: "xsd:string")
        let distinct = "<catalog>" + (0 ..< 500).map { "<item v=\"i\($0)\"/>" }.joined() + "</catalog>"
        #expect(try schema.validate(distinct).isEmpty)
        let repeated = "<catalog>" + (0 ..< 499).map { "<item v=\"i\($0)\"/>" }.joined() + "<item v=\"i0\"/></catalog>"
        #expect(try !schema.validate(repeated).isEmpty)
    }

    @Test("a whitespace-collapsing duplicate the raw path skips is caught by the fallback")
    func test_collapseFallback() throws {
        // xsd:token collapses internal runs, so "a  b" and "a b" are one value.
        // Selected by xsi:type so the field carries the token type, it is not
        // whitespace-preserving and so bypasses the raw-string Set, colliding only
        // through the exact value-space scan.
        let schema = try PureXML.Schema.Document("""
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <xsd:element name="catalog">
            <xsd:complexType><xsd:sequence>
              <xsd:element name="item" type="xsd:anyType" maxOccurs="unbounded"/>
            </xsd:sequence></xsd:complexType>
            <xsd:unique name="u"><xsd:selector xpath="item"/><xsd:field xpath="."/></xsd:unique>
          </xsd:element>
        </xsd:schema>
        """)
        func doc(_ first: String, _ second: String) -> String {
            "<catalog xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">"
                + "<item xsi:type=\"xsd:token\">\(first)</item><item xsi:type=\"xsd:token\">\(second)</item></catalog>"
        }
        #expect(try !schema.validate(doc("a  b", "a b")).isEmpty)
        #expect(try schema.validate(doc("a b", "c d")).isEmpty)
    }

    @Test("a colon-bearing string duplicate is still caught")
    func test_colonValue() throws {
        // A value with a colon is conservatively routed to the value-space scan
        // (it could be a QName), so duplicates must still be detected.
        let schema = try uniqueSchema(field: "@v", type: "xsd:string")
        #expect(try !schema.validate("<catalog><item v=\"a:b\"/><item v=\"a:b\"/></catalog>").isEmpty)
    }

    @Test("a duplicate among many same-name siblings keeps its positional location")
    func test_errorLocationPredicate() throws {
        let schema = try uniqueSchema(field: "@v", type: "xsd:string")
        let doc = "<catalog>" + (0 ..< 5).map { "<item v=\"i\($0)\"/>" }.joined() + "<item v=\"i0\"/></catalog>"
        let errors = try schema.validate(doc)
        #expect(errors.count == 1)
        // The sixth item collides; its located path names item[6], proving the
        // cached sibling index numbers the colliding target correctly.
        #expect(errors.first.map { "\($0)".contains("item") && "\($0)".contains("6") } == true)
    }
}
