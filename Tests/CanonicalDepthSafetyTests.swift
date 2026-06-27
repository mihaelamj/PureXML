import Testing
@testable import PureXML

/// The Canonical XML transforms that were still recursive must not overflow on a
/// deeply-nested tree (#350): the C14N 2.0 sequential prefix rewrite (its
/// document-order assignment pass and its rebuild pass) and the node-subset
/// serializer. Both now drive explicit work stacks; these reach depths the
/// recursive forms could not survive. The main inclusive serializer is covered by
/// `TransformDepthSafetyTests`.
@Suite("Canonical depth safety")
struct CanonicalDepthSafetyTests {
    private let namespace = "urn:t"

    /// A `depth`-deep chain of namespaced `x:a` elements, the outermost declaring
    /// the namespace, with a text leaf at the bottom.
    private func deepNamespacedDocument(_ depth: Int) -> PureXML.Model.Node {
        let name = PureXML.Model.QualifiedName(prefix: "x", localName: "a", namespaceURI: namespace)
        var node: PureXML.Model.Node = .element(.init(name: name, attributes: [], children: [.text("leaf")]))
        for index in 1 ..< depth {
            let attributes: [PureXML.Model.Attribute] = index == depth - 1 ? [.init("xmlns:x", namespace)] : []
            node = .element(.init(name: name, attributes: attributes, children: [node]))
        }
        return .document([node])
    }

    @Test("the C14N 2.0 sequential prefix rewrite is depth-safe")
    func test_deepPrefixRewrite() {
        let depth = 50000
        let options = PureXML.Canonical.Options(prefixRewrite: .sequential)
        let canonical = PureXML.Canonical.canonicalize(deepNamespacedDocument(depth), options: options)
        // Every element is renamed to the single canonical prefix n0, declared once.
        #expect(canonical.contains("leaf"))
        #expect(canonical.contains("xmlns:n0=\"\(namespace)\""))
        #expect(canonical.components(separatedBy: "</n0:a>").count - 1 == depth)
    }

    @Test("the node-subset canonicalizer is depth-safe")
    func test_deepNodeSubset() {
        let depth = 50000
        let document = PureXML.Model.TreeNode(deepNamespacedDocument(depth))
        let canonical = PureXML.Canonical.Canonicalizer(options: .inclusive).canonicalize(document) { _ in true }
        #expect(canonical.contains("leaf"))
        #expect(canonical.components(separatedBy: "</x:a>").count - 1 == depth)
    }
}
