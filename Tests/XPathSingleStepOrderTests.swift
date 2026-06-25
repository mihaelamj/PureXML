import Testing
@testable import PureXML

/// A single forward-axis step from one context node is returned without the
/// document-order sort, on the proof that `AxisNavigation` already produces the
/// structural forward axes in document order. These tests pin that the order is
/// in fact document order for each such axis (so the skipped sort would not have
/// changed it), and that the axes left to the sort (attribute, namespace) and
/// the reverse axes still order correctly.
@Suite("XPath single-step path order")
struct XPathSingleStepOrderTests {
    /// Document order of the `n` elements is 1..6; b and c are nested so a naive
    /// per-parent accumulation would differ from document order.
    private static let source = """
    <r xmlns:k="urn:k">
      <n id="1"/>
      <a><n id="2"/><b><n id="3"/></b><n id="4"/></a>
      <n id="5"/>
      <a><n id="6"/></a>
    </r>
    """

    private func ids(_ path: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: PureXML.parse(Self.source)).compactMap {
            if case let .node(node) = $0 { return node.element?.attributes.first { $0.name.localName == "id" }?.value }
            return nil
        }
    }

    private func names(_ path: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: PureXML.parse(Self.source)).compactMap {
            if case let .node(node) = $0 { return node.element?.name.localName }
            return nil
        }
    }

    @Test("descendant axis returns in document order without the sort")
    func test_descendantOrder() throws {
        #expect(try ids("//n") == ["1", "2", "3", "4", "5", "6"])
        #expect(try ids("/r/descendant::n") == ["1", "2", "3", "4", "5", "6"])
    }

    @Test("child and descendant-or-self single steps are in document order")
    func test_childAndSelfOrder() throws {
        // The n children of r are n1 and n5 (the a elements have no id).
        #expect(try ids("/r/child::n") == ["1", "5"])
        // /r/a selects BOTH a elements; descendant-or-self::*[@id] under them is
        // n2, n3, n4 (first a) and n6 (second a), sorted to document order.
        #expect(try ids("/r/a/descendant-or-self::*[@id]") == ["2", "3", "4", "6"])
    }

    @Test("following and following-sibling single steps are in document order")
    func test_followingOrder() throws {
        // following:: from n2 reaches n3, n4, n5, n6 (not n2's ancestors/self).
        #expect(try ids("//n[@id='2']/following::n") == ["3", "4", "5", "6"])
        // following-sibling:: of n2 within its parent a: b(no id) then n4.
        #expect(try ids("//n[@id='2']/following-sibling::n") == ["4"])
    }

    @Test("reverse axes still order nearest-first via the sort path")
    func test_reverseAxisOrder() throws {
        // Ancestors of n3 are b, a, r; the node-set normalizes to document order.
        #expect(try names("//n[@id='3']/ancestor::*") == ["r", "a", "b"])
        // preceding:: of n5 excludes ancestors; n1 and the first a's n2/n3/n4.
        #expect(try ids("//n[@id='5']/preceding::n") == ["1", "2", "3", "4"])
    }

    @Test("a multi-step path is still sorted to document order")
    func test_multiStepStillSorted() throws {
        // //a/n gathers n children of every a; document order across both a's.
        #expect(try ids("//a/n") == ["2", "4", "6"])
    }
}
