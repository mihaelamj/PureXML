import Testing
@testable import PureXML

@Suite("Canonical XML: node-subset canonicalization and xml:* inheritance")
struct CanonicalSubsetTests {
    /// The document is held for the duration of each test: a TreeNode's parent
    /// link is weak, so the canonicalizer only sees a node's ancestors while the
    /// tree that owns them is alive (the standard DOM top-down ownership).
    private func canonicalize(_ xml: String, at path: [Int], _ options: PureXML.Canonical.Options) throws -> String {
        let document = try PureXML.parseTree(xml)
        var node = document
        for index in path {
            node = node.children[index]
        }
        return PureXML.Canonical.Canonicalizer(options: options).canonicalize(node)
    }

    @Test("An inclusive subtree renders the namespaces in scope from its ancestors")
    func test_inheritedNamespace() throws {
        let output = try canonicalize("<root xmlns:p=\"urn:x\"><p:child><p:gc/></p:child></root>", at: [0, 0], .inclusive)
        #expect(output == "<p:child xmlns:p=\"urn:x\"><p:gc></p:gc></p:child>")
    }

    @Test("A subtree inherits xml:lang and xml:space from omitted ancestors")
    func test_inheritedXMLAttributes() throws {
        let output = try canonicalize("<root xml:lang=\"en\" xml:space=\"preserve\"><child><gc/></child></root>", at: [0, 0], .inclusive)
        #expect(output == "<child xml:lang=\"en\" xml:space=\"preserve\"><gc></gc></child>")
    }

    @Test("The apex's own xml:* attribute overrides an inherited one")
    func test_apexOverridesInherited() throws {
        let output = try canonicalize("<root xml:lang=\"en\"><child xml:lang=\"fr\"/></root>", at: [0, 0], .inclusive)
        #expect(output == "<child xml:lang=\"fr\"></child>")
    }

    @Test("An exclusive subtree renders only the ancestor namespaces it uses")
    func test_exclusiveOnlyUsed() throws {
        let output = try canonicalize("<root xmlns:p=\"urn:x\" xmlns:q=\"urn:y\"><p:child/></root>", at: [0, 0], .exclusive)
        #expect(output == "<p:child xmlns:p=\"urn:x\"></p:child>")
    }

    @Test("A nearer ancestor's namespace binding wins over a farther one")
    func test_nearestNamespaceWins() throws {
        let output = try canonicalize("<a xmlns:p=\"urn:far\"><b xmlns:p=\"urn:near\"><p:c/></b></a>", at: [0, 0, 0], .inclusive)
        #expect(output == "<p:c xmlns:p=\"urn:near\"></p:c>")
    }
}
