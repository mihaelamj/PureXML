import Testing
@testable import PureXML

/// Ordering facets on `xs:duration` (#147). Duration is a partial order (a month
/// is 28 to 31 days), compared by adding to four reference dateTimes. The bounds
/// had not been enforced at all; a value incomparable to the bound (such as
/// `P1M` against `P30D`) is outside the range and must be rejected.
@Suite("Duration ordering facets")
struct SchemaDurationFacetTests {
    private func schema(_ facet: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v">
            <xs:simpleType>
              <xs:restriction base="xs:duration">\(facet)</xs:restriction>
            </xs:simpleType>
          </xs:element>
        </xs:schema>
        """)
    }

    @Test("minInclusive enforces the lower bound")
    func test_minInclusive() throws {
        let doc = try schema(#"<xs:minInclusive value="P1Y"/>"#)
        #expect(try doc.validate("<v>P1Y</v>").isEmpty) // equal
        #expect(try doc.validate("<v>P2Y</v>").isEmpty) // greater
        #expect(try !doc.validate("<v>P6M</v>").isEmpty) // less
    }

    @Test("minExclusive rejects the bound itself")
    func test_minExclusive() throws {
        let doc = try schema(#"<xs:minExclusive value="P1Y"/>"#)
        #expect(try !doc.validate("<v>P1Y</v>").isEmpty) // equal: rejected
        #expect(try doc.validate("<v>P2Y</v>").isEmpty) // greater
    }

    @Test("maxInclusive enforces the upper bound and rejects incomparable values")
    func test_maxInclusivePartialOrder() throws {
        let doc = try schema(#"<xs:maxInclusive value="P30D"/>"#)
        #expect(try doc.validate("<v>P20D</v>").isEmpty) // less
        #expect(try !doc.validate("<v>P40D</v>").isEmpty) // greater
        // P1M is incomparable to P30D (28..31 days) so it is not <= P30D.
        #expect(try !doc.validate("<v>P1M</v>").isEmpty)
    }
}
