import Testing
@testable import PureXML

/// String-value extraction must not recurse on a node's depth (#350). Computing
/// the concatenated character data of an element walked its subtree recursively,
/// so it overflowed the stack on a deeply-nested node (as shallow as a couple of
/// thousand deep on a Swift Task stack, which these tests run on). The walk is
/// now iterative; these tests reach depths the recursive form could not survive.
@Suite("String-value depth safety")
struct StringValueDepthSafetyTests {
    private func deepDocument(_ depth: Int, leaf: String) -> PureXML.Model.Node {
        var node: PureXML.Model.Node = .text(leaf)
        for index in 0 ..< depth {
            // A comment sibling at each level proves comments do not contribute to
            // the XPath string-value of an element.
            node = .element(.init("a", children: [.comment("c\(index)"), node]))
        }
        return .document([node])
    }

    @Test("strings() on a 50k-deep node returns the leaf text without overflowing")
    func test_deepStringValueIsBounded() throws {
        let document = deepDocument(50000, leaf: "leaf")
        let strings = try PureXML.XPath.Query("/a").strings(over: document)
        #expect(strings == ["leaf"]) // comments excluded from an element's string-value
    }

    @Test("TreeNode.textContent on a deep subtree is iterative and excludes comments")
    func test_deepTextContentIsBounded() {
        let tree = PureXML.Model.TreeNode(deepDocument(50000, leaf: "deep"))
        #expect(tree.textContent == "deep")
    }

    @Test("string-value concatenates descendant text in document order")
    func test_stringValueOrderAndContent() throws {
        let xml = "<r>one<a>two</a>three<b>four</b></r>"
        let strings = try PureXML.XPath.Query("/r").strings(over: PureXML.parse(xml))
        #expect(strings == ["onetwothreefour"])
    }
}
