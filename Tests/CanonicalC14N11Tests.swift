@testable import PureXML
import Testing

@Suite("Canonical XML 1.1: xml:base merging and xml:id")
struct CanonicalC14N11Tests {
    private func canonicalize(_ xml: String, at path: [Int], _ options: PureXML.Canonical.Options) throws -> String {
        let document = try PureXML.parseTree(xml)
        var node = document
        for index in path {
            node = node.children[index]
        }
        return PureXML.Canonical.Canonicalizer(options: options).canonicalize(node)
    }

    @Test("1.1 merges the omitted-ancestor xml:base chain; 1.0 takes the nearest")
    func test_baseMerging() throws {
        let xml = "<root xml:base=\"http://example.org/a/\"><mid xml:base=\"b/\"><apex/></mid></root>"
        try #expect(canonicalize(xml, at: [0, 0, 0], .canonical11) == "<apex xml:base=\"http://example.org/a/b/\"></apex>")
        try #expect(canonicalize(xml, at: [0, 0, 0], .inclusive) == "<apex xml:base=\"b/\"></apex>")
    }

    @Test("1.1 resolves the apex's own relative xml:base against the inherited chain")
    func test_apexRelativeBase() throws {
        let xml = "<root xml:base=\"http://example.org/a/\"><apex xml:base=\"c/d\"/></root>"
        try #expect(canonicalize(xml, at: [0, 0], .canonical11) == "<apex xml:base=\"http://example.org/a/c/d\"></apex>")
        // 1.0 keeps the apex's own base unresolved (no merge).
        try #expect(canonicalize(xml, at: [0, 0], .inclusive) == "<apex xml:base=\"c/d\"></apex>")
    }

    @Test("1.1 resolves dot segments in the merged base")
    func test_dotSegments() throws {
        let xml = "<root xml:base=\"http://example.org/a/b/\"><apex xml:base=\"../x\"/></root>"
        try #expect(canonicalize(xml, at: [0, 0], .canonical11) == "<apex xml:base=\"http://example.org/a/x\"></apex>")
    }

    @Test("1.1 does not inherit xml:id; 1.0 does")
    func test_xmlIdNotInherited() throws {
        let xml = "<root xml:id=\"r\"><apex/></root>"
        try #expect(canonicalize(xml, at: [0, 0], .canonical11) == "<apex></apex>")
        try #expect(canonicalize(xml, at: [0, 0], .inclusive) == "<apex xml:id=\"r\"></apex>")
    }

    @Test("1.1 still inherits xml:lang and xml:space (nearest)")
    func test_langSpaceStillInherited() throws {
        let xml = "<root xml:lang=\"en\" xml:space=\"preserve\"><apex/></root>"
        try #expect(canonicalize(xml, at: [0, 0], .canonical11) == "<apex xml:lang=\"en\" xml:space=\"preserve\"></apex>")
    }
}
