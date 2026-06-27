import Testing
@testable import PureXML

/// XInclude processing must not recurse on a tree's depth (#350). The pass
/// rebuilt the tree recursively, so a deeply-nested document overflowed the
/// stack (as shallow as a couple of thousand deep on a Swift Task stack), even
/// with no includes present. It now drives an explicit work stack; these tests
/// reach depths the recursive form could not survive, for both a plain tree and
/// a deep included resource.
@Suite("XInclude depth safety")
struct XIncludeDepthSafetyTests {
    private func deepDocument(_ depth: Int, root: String, leaf: String) -> PureXML.Model.Node {
        var node: PureXML.Model.Node = .text(leaf)
        for _ in 0 ..< depth {
            node = .element(.init("a", children: [node]))
        }
        return .document([.element(.init(root, children: [node]))])
    }

    /// The nesting depth of the first-child chain and the deepest text leaf.
    private func descend(_ node: PureXML.Model.Node) -> (depth: Int, leaf: String?) {
        var current = node
        var depth = 0
        while true {
            switch current {
            case let .document(children):
                guard let first = children.first else { return (depth, nil) }
                current = first
            case let .element(element):
                guard let first = element.children.first else { return (depth, nil) }
                depth += 1
                current = first
            case let .text(value), let .cdata(value):
                return (depth, value)
            default:
                return (depth, nil)
            }
        }
    }

    @Test("processing a 50k-deep document with no includes does not overflow")
    func test_deepPlainTreeIsBounded() throws {
        let document = deepDocument(50000, root: "doc", leaf: "leaf")
        let result = try PureXML.XInclude.process(document, loadingURI: { _ in nil })
        // root <doc> plus 50000 <a>, with the leaf preserved.
        let descended = descend(result)
        #expect(descended.depth == 50001)
        #expect(descended.leaf == "leaf")
    }

    @Test("an include at the bottom of a deep tree resolves without overflowing")
    func test_includeDeepInTreeIsBounded() throws {
        // A 50k-deep chain whose innermost child is an xi:include, so the include
        // is resolved at the bottom of the iterative walk.
        let depth = 50000
        var node: PureXML.Model.Node = .element(.init("xi:include", attributes: [.init("href", "x.xml")]))
        for _ in 0 ..< depth {
            node = .element(.init("a", children: [node]))
        }
        let document = PureXML.Model.Node.document([.element(.init("doc", children: [node]))])
        let result = try PureXML.XInclude.process(document, loadingURI: { uri in
            uri == "x.xml" ? "<x>hi</x>" : nil
        })
        let descended = descend(result)
        // <doc> -> 50000 <a> -> spliced <x> -> "hi".
        #expect(descended.depth == depth + 2)
        #expect(descended.leaf == "hi")
    }
}
