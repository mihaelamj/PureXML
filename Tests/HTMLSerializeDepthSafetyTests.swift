import Testing
@testable import PureXML

/// HTML serialization must not recurse on a tree's depth (#350). The serializer
/// walked an element's children recursively, so it overflowed the stack on a
/// deeply-nested tree (as shallow as a couple of thousand deep on the Swift Task
/// stack these tests run on). It now drives a deferred-close work stack; these
/// tests reach depths the recursive form could not survive, and pin the
/// raw-text, void, and escaping semantics the refactor must preserve.
@Suite("HTML serialize depth safety")
struct HTMLSerializeDepthSafetyTests {
    private func deepTree(_ depth: Int, leaf: String) -> PureXML.Model.Node {
        var node: PureXML.Model.Node = .text(leaf)
        for _ in 0 ..< depth {
            node = .element(.init("div", children: [node]))
        }
        return node
    }

    @Test("serialize on a 50k-deep tree emits balanced tags without overflowing")
    func test_deepSerializeIsBounded() {
        let depth = 50000
        let html = PureXML.HTML.serialize(deepTree(depth, leaf: "leaf"))
        #expect(html.hasPrefix(String(repeating: "<div>", count: depth) + "leaf"))
        #expect(html.hasSuffix(String(repeating: "</div>", count: depth)))
    }

    @Test("raw-text, void, comment, and escaping semantics are unchanged")
    func test_semanticsPreserved() {
        // A raw-text element writes its own text verbatim; a nested element still
        // serializes by its own name; text outside is escaped; a void element has
        // no end tag and drops nested content.
        let tree: PureXML.Model.Node = .element(.init("body", children: [
            .element(.init("script", children: [.text("if (a < b) x()")])),
            .text("a < b & c"),
            .element(.init("br", children: [.text("dropped")])),
            .comment(" note "),
        ]))
        let html = PureXML.HTML.serialize(tree)
        #expect(html == "<body><script>if (a < b) x()</script>a &lt; b &amp; c<br><!-- note --></body>")
    }
}
