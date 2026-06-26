import Testing
@testable import PureXML

/// Namespace resolution must not make parsing quadratic in nesting depth (#345).
/// Each open element resolves its name against the in-scope bindings; doing that
/// by walking a scope stack as deep as the document made parsing O(depth^2). The
/// bindings are now maintained incrementally, so a lookup is O(1) and parsing is
/// linear. The time limit turns a regression back to quadratic into a failure
/// rather than a silent interactive hang: at this depth the old behaviour took
/// minutes, the linear one takes well under a second.
@Suite("Namespace resolution scale (#345)")
struct NamespaceScaleTests {
    #if os(WASI)
        @Test("a deeply-nested document parses in linear time")
    #else
        @Test("a deeply-nested document parses in linear time", .timeLimit(.minutes(1)))
    #endif
    func test_deepNestingParsesLinearly() throws {
        let depth = 100_000
        let xml = String(repeating: "<a x=\"1\">", count: depth) + "leaf" + String(repeating: "</a>", count: depth)
        let node = try PureXML.parse(xml, limits: .init(maxDepth: depth + 1))
        // The parse produced the leaf at the bottom of the nesting.
        #expect(PureXML.serialize(node, options: .compact).contains("leaf"))
    }

    @Test("nested default-namespace bindings still resolve to the nearest in scope")
    func test_nearestBindingWins() throws {
        let xml = """
        <a xmlns="urn:outer"><b xmlns="urn:inner"><c/></b><d/></a>
        """
        let node = try PureXML.parse(xml)
        guard case let .document(roots) = node, let root = roots.first(where: { $0.element != nil })?.element else {
            Issue.record("expected a document with a root element")
            return
        }
        #expect(root.name.namespaceURI == "urn:outer") // a
        let inner = root.children.first(where: { $0.element?.name.localName == "b" })?.element
        let outerSibling = root.children.first(where: { $0.element?.name.localName == "d" })?.element
        #expect(inner?.name.namespaceURI == "urn:inner") // b: nearer default binding
        #expect(inner?.children.first(where: { $0.element?.name.localName == "c" })?.element?.name.namespaceURI == "urn:inner") // c inherits inner
        #expect(outerSibling?.name.namespaceURI == "urn:outer") // d: inner binding popped, back to outer
    }
}
