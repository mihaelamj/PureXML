import Testing
@testable import PureXML

/// The attribute axis over a tree context fuses the node test into the walk
/// (`matchesAttribute`), so an attribute the test rejects is never wrapped.
/// These tests pin that every node-test kind selects exactly what the unfused
/// `matches` path would: a name test (plain and namespaced), the principal-kind
/// wildcard, `node()`, and the kind tests (which never select an attribute).
@Suite("XPath fused attribute node tests")
struct XPathFusedAttributeTests {
    private static let source =
        #"<r xmlns:k="urn:k"><e a="1" b="2" k:c="3"/><e a="4"/></r>"#

    private func values(_ path: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: PureXML.parse(Self.source)).compactMap {
            if case let .attribute(attribute) = $0 { return attribute.value }
            return nil
        }
    }

    private func count(_ path: String) throws -> Int {
        try Int(PureXML.XPath.Query("count(\(path))").value(at: PureXML.parseTree(Self.source)).number)
    }

    @Test("a name test selects the matching attribute only")
    func test_nameTest() throws {
        #expect(try values("//e/@a") == ["1", "4"])
        #expect(try values("//e/@b") == ["2"])
        #expect(try values("//e/@missing") == [])
    }

    @Test("a namespaced attribute name test resolves the prefix")
    func test_namespacedName() throws {
        #expect(try values("//e/@k:c") == ["3"])
    }

    @Test("the wildcard selects every attribute (excluding namespace declarations)")
    func test_wildcard() throws {
        // First e has a, b, k:c (3); second has a (1). xmlns:k is not an attribute node.
        #expect(try count("//e/@*") == 4)
        #expect(try count("/r/@*") == 0) // r has only the xmlns:k declaration
    }

    @Test("kind tests never select an attribute; node() does")
    func test_kindAndNode() throws {
        #expect(try count("//e/attribute::text()") == 0)
        #expect(try count("//e/attribute::comment()") == 0)
        // attribute::node() selects every attribute.
        #expect(try count("//e/attribute::node()") == 4)
    }

    @Test("a predicate over a fused attribute selection still filters")
    func test_predicate() throws {
        #expect(try values("//e[@a='4']/@a") == ["4"])
        #expect(try count("//e[@b]") == 1) // only the first e has a b attribute
    }
}
