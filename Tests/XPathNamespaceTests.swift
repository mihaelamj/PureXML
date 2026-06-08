@testable import PureXML
import Testing

@Suite("XPath eval-time namespaces and XPointer schemes")
struct XPathNamespaceTests {
    @Test("A name test resolves through eval-time prefix bindings regardless of document prefix")
    func test_evalTimeNamespace() throws {
        // The document uses prefix 'd'; the query uses 'q' bound to the same URI.
        let node = try PureXML.parse("<d:root xmlns:d=\"urn:x\"><d:item/></d:root>")
        let query = try PureXML.XPath.Query("//q:item")
        let bound = query.evaluate(over: node, namespaces: ["q": "urn:x"])
        #expect(bound.count == 1)
        // Without the binding, the query prefix 'q' does not match the document's 'd'.
        #expect(query.evaluate(over: node).isEmpty)
    }

    @Test("A binding to the wrong URI does not match")
    func test_wrongNamespace() throws {
        let node = try PureXML.parse("<d:root xmlns:d=\"urn:x\"><d:item/></d:root>")
        let query = try PureXML.XPath.Query("//q:item")
        #expect(query.evaluate(over: node, namespaces: ["q": "urn:other"]).isEmpty)
    }

    @Test("Existing unprefixed queries are unaffected by an empty binding set")
    func test_noBindingUnchanged() throws {
        let node = try PureXML.parse("<root><item/><item/></root>")
        #expect(try PureXML.XPath.Query("//item").evaluate(over: node).count == 2)
    }

    @Test("XPointer xpath1() evaluates an XPath expression")
    func test_xpath1Scheme() throws {
        let node = try PureXML.parse("<root><item/><item/></root>")
        let result = try PureXML.XPointer.evaluate("xpath1(//item)", over: node)
        #expect(result.count == 2)
    }

    @Test("XPointer xmlns() binds a prefix for the following xpointer part")
    func test_xmlnsScheme() throws {
        let node = try PureXML.parse("<d:root xmlns:d=\"urn:x\"><d:item/></d:root>")
        let result = try PureXML.XPointer.evaluate("xmlns(q=urn:x)xpointer(//q:item)", over: node)
        #expect(result.count == 1)
    }

    @Test("XPointer falls through schemes until one selects")
    func test_schemeFallback() throws {
        let node = try PureXML.parse("<root><item/></root>")
        // The first xpointer selects nothing; the second selects the item.
        let result = try PureXML.XPointer.evaluate("xpointer(//missing)xpointer(//item)", over: node)
        #expect(result.count == 1)
    }
}
