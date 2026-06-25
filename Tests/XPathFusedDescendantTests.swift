import Testing
@testable import PureXML

/// The descendant and descendant-or-self axes over a tree context fuse the node
/// test into the traversal (`matchesTree`), so a node the test rejects is never
/// wrapped. These tests pin that every node-test kind selects exactly what the
/// unfused `matches` path would, across element names, the principal-kind
/// wildcard, and the `text()`/`comment()`/`processing-instruction()`/`node()`
/// kind tests, including namespaced names.
@Suite("XPath fused descendant node tests")
struct XPathFusedDescendantTests {
    /// No inter-element whitespace, so the only text node is "text-a".
    private static let source =
        #"<r xmlns:k="urn:k"><a id="1">text-a<k:b id="2"/><!--c--><?pi go?></a><a id="3"><d><k:b id="4"/></d></a></r>"#

    private func count(_ path: String) throws -> Int {
        try Int(PureXML.XPath.Query("count(\(path))").value(at: PureXML.parseTree(Self.source)).number)
    }

    private func ids(_ path: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: PureXML.parse(Self.source)).compactMap {
            if case let .node(node) = $0 { return node.element?.attributes.first { $0.name.localName == "id" }?.value }
            return nil
        }
    }

    @Test("element name test under // selects the right elements in order")
    func test_nameTest() throws {
        #expect(try ids("//a") == ["1", "3"])
        // Namespaced name test resolves the in-document prefix.
        #expect(try ids("//k:b") == ["2", "4"])
        #expect(try count("//d") == 1)
    }

    @Test("the principal-kind wildcard under // selects only elements")
    func test_wildcard() throws {
        // Elements: r, a, k:b, a, d, k:b = 6 (the descendant-or-self of //* counts r too).
        #expect(try count("//*") == 6)
        // descendant-or-self::* from the root is the same set.
        #expect(try count("/descendant-or-self::*") == 6)
    }

    @Test("the kind tests under // select the right node kinds")
    func test_kindTests() throws {
        #expect(try count("//text()") == 1) // "text-a"
        #expect(try count("//comment()") == 1) // <!--c-->
        #expect(try count("//processing-instruction()") == 1) // <?pi go?>
        #expect(try count("//processing-instruction('pi')") == 1)
        #expect(try count("//processing-instruction('other')") == 0)
        // node() matches every node kind under the document element.
        #expect(try count("//node()") >= 6)
    }

    @Test("a predicate still filters the fused descendant result")
    func test_predicateOnFused() throws {
        #expect(try ids("//a[@id='3']") == ["3"])
        #expect(try ids("//k:b[1]") == ["2", "4"]) // first k:b child of EACH parent
    }
}
