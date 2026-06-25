import Testing
@testable import PureXML

/// An attribute node's document-order key bands by its index among its owner's
/// attributes. That index now comes from a cached per-owner name-to-index map
/// (built once on the second lookup) rather than a linear scan per attribute,
/// so sorting many attribute nodes from one element is linear, not quadratic.
/// These pin that the order is unchanged: declaration order, for attributes
/// handed to the sort out of order, including a many-attribute element.
@Suite("attribute document order")
struct AttributeDocumentOrderTests {
    private func values(_ path: String, _ xml: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: PureXML.parse(xml)).compactMap {
            if case let .attribute(attribute) = $0 { return attribute.value }
            return nil
        }
    }

    @Test("a union of attributes comes back in declaration order")
    func test_unionOrder() throws {
        let xml = #"<e a="1" b="2" c="3" d="4"/>"#
        // The union lists them out of declaration order; the result is the
        // deduplicated node-set in document (declaration) order.
        #expect(try values("//e/@c | //e/@a | //e/@d | //e/@b", xml) == ["1", "2", "3", "4"])
    }

    @Test("attributes of a many-attribute element sort in declaration order")
    func test_manyAttributes() throws {
        // The quadratic-prone case: one element with many attributes, all sorted.
        var attrs = ""
        for index in 0 ..< 200 {
            attrs += " a\(index)=\"\(index)\""
        }
        let xml = "<e\(attrs)/>"
        let ordered = try values("//e/@* | //e/@*", xml)
        #expect(ordered.count == 200)
        #expect(ordered == (0 ..< 200).map(String.init))
    }
}
