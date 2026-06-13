@testable import PureXML
import Testing

/// Length facets on the built-in list datatypes (`NMTOKENS`, `IDREFS`,
/// `ENTITIES`) count list items, not characters (#146). A restriction of one of
/// these built-ins had collapsed to an atomic string, so `length` measured
/// characters and rejected valid instances across the XSTS NIST list sets.
@Suite("List datatype length facets")
struct SchemaListFacetTests {
    private func schema(_ base: String, _ facet: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v">
            <xs:simpleType>
              <xs:restriction base="\(base)">\(facet)</xs:restriction>
            </xs:simpleType>
          </xs:element>
        </xs:schema>
        """)
    }

    @Test("length on NMTOKENS counts items, not characters")
    func test_nmtokensLength() throws {
        let doc = try schema("xs:NMTOKENS", #"<xs:length value="3"/>"#)
        #expect(try doc.validate("<v>alpha beta gamma</v>").isEmpty) // 3 items: valid
        #expect(try !doc.validate("<v>alpha beta</v>").isEmpty) // 2 items: invalid
        #expect(try !doc.validate("<v>alpha beta gamma delta</v>").isEmpty) // 4 items: invalid
    }

    @Test("minLength and maxLength on IDREFS count items")
    func test_idrefsMinMax() throws {
        let doc = try schema("xs:IDREFS", #"<xs:minLength value="2"/><xs:maxLength value="3"/>"#)
        #expect(try doc.validate("<v>a b</v>").isEmpty) // 2 items: valid
        #expect(try doc.validate("<v>a b c</v>").isEmpty) // 3 items: valid
        #expect(try !doc.validate("<v>a</v>").isEmpty) // 1 item: invalid
        #expect(try !doc.validate("<v>a b c d</v>").isEmpty) // 4 items: invalid
    }
}
