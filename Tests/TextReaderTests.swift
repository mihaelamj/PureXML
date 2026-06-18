import Testing
@testable import PureXML

@Suite("Text reader")
struct TextReaderTests {
    private typealias Kind = PureXML.Parsing.ReaderNodeKind

    private struct NodeSnapshot {
        let kind: Kind
        let name: String
        let value: String
        let depth: Int
    }

    /// Drains a reader into a list of node snapshots.
    private func drain(_ xml: String) throws -> [NodeSnapshot] {
        var reader = PureXML.reader(xml)
        var nodes: [NodeSnapshot] = []
        while try reader.read() {
            nodes.append(NodeSnapshot(
                kind: reader.nodeKind,
                name: reader.name,
                value: reader.value,
                depth: reader.depth,
            ))
        }
        return nodes
    }

    @Test("Before the first read the cursor is on no node")
    func test_initialState() {
        let reader = PureXML.reader("<r/>")
        #expect(reader.nodeKind == .none)
        #expect(reader.depth == 0)
    }

    @Test("Elements, text, and end elements are reported with depth")
    func test_walk() throws {
        let nodes = try drain("<r><a>hi</a></r>")
        #expect(nodes.map(\.kind) == [.element, .element, .text, .endElement, .endElement])
        #expect(nodes.map(\.name) == ["r", "a", "#text", "a", "r"])
        #expect(nodes.map(\.depth) == [0, 1, 2, 1, 0])
        #expect(nodes[2].value == "hi")
    }

    @Test("A childless element is a single empty-element node")
    func test_emptyElement() throws {
        var reader = PureXML.reader("<r><a/></r>")
        #expect(try reader.read())
        #expect(reader.nodeKind == .element)
        #expect(reader.name == "r")
        #expect(!reader.isEmptyElement)
        #expect(try reader.read())
        #expect(reader.name == "a")
        #expect(reader.isEmptyElement)
        // The empty element is not followed by a separate end node.
        #expect(try reader.read())
        #expect(reader.nodeKind == .endElement)
        #expect(reader.name == "r")
        #expect(try !reader.read())
    }

    @Test("An explicit empty pair is normalized to one empty element")
    func test_explicitEmptyPair() throws {
        let nodes = try drain("<r></r>")
        #expect(nodes.count == 1)
        #expect(nodes[0].kind == .element)
    }

    @Test("Attributes are exposed on the current element")
    func test_attributes() throws {
        var reader = PureXML.reader("<r a=\"1\" b=\"2\"/>")
        #expect(try reader.read())
        #expect(reader.attributeCount == 2)
        #expect(reader.attribute("a") == "1")
        #expect(reader.attribute("b") == "2")
        #expect(reader.attribute("c") == nil)
    }

    @Test("CDATA, comments, and processing instructions are distinguished")
    func test_otherNodeKinds() throws {
        let nodes = try drain("<r><![CDATA[x]]><!--c--><?pi d?></r>")
        #expect(nodes.map(\.kind) == [.element, .cdata, .comment, .processingInstruction, .endElement])
        #expect(nodes[1].value == "x")
        #expect(nodes[2].value == "c")
        #expect(nodes[3].name == "pi")
        #expect(nodes[3].value == "d")
    }

    @Test("Attributes are cleared when moving off an element")
    func test_attributesCleared() throws {
        var reader = PureXML.reader("<r a=\"1\">text</r>")
        #expect(try reader.read())
        #expect(reader.attributeCount == 1)
        #expect(try reader.read())
        #expect(reader.nodeKind == .text)
        #expect(reader.attributeCount == 0)
    }
}
