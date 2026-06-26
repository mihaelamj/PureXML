import Testing
@testable import PureXML

/// Tree-to-tree transforms must not recurse on a document's depth (#350). They
/// rebuilt the tree with a per-node recursive walk, so transforming a deeply
/// nested document overflowed the stack (as shallow as a couple of thousand deep
/// on a Swift Task stack, which these tests run on). The walks are now iterative.
@Suite("Transform depth safety")
struct TransformDepthSafetyTests {
    private func deepXML(_ depth: Int, doctype: String = "") -> String {
        doctype + String(repeating: "<a>", count: depth) + "x" + String(repeating: "</a>", count: depth)
    }

    @Test("applying DTD attribute defaults to a deep document does not overflow")
    func test_deepDTDDefaults() throws {
        let depth = 50000
        let xml = deepXML(depth, doctype: "<!DOCTYPE a [<!ATTLIST a kept CDATA \"on\">]>")
        let node = try PureXML.parseApplyingInternalDTDDefaults(xml, limits: .init(maxDepth: depth + 1, allowDoctype: true))
        // Every `a` element gained the defaulted `kept="on"` attribute; check the
        // outermost one without recursing.
        guard case let .document(roots) = node, let root = roots.first(where: { $0.element != nil })?.element else {
            Issue.record("expected a document with a root element")
            return
        }
        #expect(root.attributes.contains { $0.name.localName == "kept" && $0.value == "on" })
    }
}
