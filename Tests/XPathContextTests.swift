import Testing
@testable import PureXML

@Suite("XPath evaluation context")
struct XPathContextTests {
    @Test("A relative query evaluates against an explicit context node")
    func test_contextNode() throws {
        let tree = try PureXML.parseTree("<r><a><b>deep</b></a><a><b>other</b></a></r>")
        let firstA = tree.firstChild?.firstChild
        let value = try #require(firstA)
        let result = try PureXML.XPath.Query("b").value(at: value)
        #expect(result.string == "deep")
    }

    @Test("position() and last() reflect the supplied context")
    func test_positionAndSize() throws {
        let tree = try PureXML.parseTree("<r/>")
        let node = try #require(tree.firstChild)
        #expect(try PureXML.XPath.Query("position()").value(at: node, position: 3, size: 7).number == 3)
        #expect(try PureXML.XPath.Query("last()").value(at: node, position: 3, size: 7).number == 7)
    }

    @Test("Variable bindings are visible to the evaluated expression")
    func test_variableBindings() throws {
        let tree = try PureXML.parseTree("<r/>")
        let node = try #require(tree.firstChild)
        let value = try PureXML.XPath.Query("$x * 2").value(at: node, variables: ["x": .number(21)])
        #expect(value.number == 42)
    }

    @Test("Upward axes resolve from the context node's place in the tree")
    func test_upwardFromContext() throws {
        let tree = try PureXML.parseTree("<r id=\"root\"><a><b/></a></r>")
        let deepB = tree.firstChild?.firstChild?.firstChild
        let node = try #require(deepB)
        let result = try PureXML.XPath.Query("ancestor::r/@id").value(at: node)
        #expect(result.string == "root")
    }
}
