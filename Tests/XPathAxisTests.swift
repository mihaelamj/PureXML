import Testing
@testable import PureXML

@Suite("XPath axes")
struct XPathAxisTests {
    /// A small document with depth, siblings, attributes, and a namespace.
    private func doc() throws -> PureXML.Model.Node {
        try PureXML.parse(
            "<root xmlns:k=\"urn:k\">"
                + "<a id=\"1\"><b><c/></b></a>"
                + "<a id=\"2\"><d/></a>"
                + "<e k:m=\"v\"/>"
                + "</root>",
        )
    }

    private func names(_ path: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: doc()).compactMap { selection in
            switch selection {
            case let .node(node): node.element?.name.description
            case let .attribute(attribute): attribute.name.description
            }
        }
    }

    @Test("child axis selects immediate element children")
    func test_child() throws {
        #expect(try names("/root/child::a") == ["a", "a"])
    }

    @Test("descendant axis reaches any depth")
    func test_descendant() throws {
        #expect(try names("/root/descendant::c") == ["c"])
    }

    @Test("parent axis and .. climb one level")
    func test_parent() throws {
        #expect(try names("//c/parent::b") == ["b"])
        #expect(try names("//c/..") == ["b"])
    }

    @Test("ancestor axis lists every enclosing element nearest first")
    func test_ancestor() throws {
        #expect(try names("//c/ancestor::*") == ["root", "a", "b"])
    }

    @Test("ancestor-or-self includes the context node")
    func test_ancestorOrSelf() throws {
        #expect(try names("//c/ancestor-or-self::*") == ["root", "a", "b", "c"])
    }

    @Test("following-sibling and preceding-sibling walk siblings")
    func test_siblings() throws {
        #expect(try names("/root/a[1]/following-sibling::*") == ["a", "e"])
        #expect(try names("/root/e/preceding-sibling::*") == ["a", "a"])
    }

    @Test("following axis selects nodes after the context, excluding descendants")
    func test_following() throws {
        #expect(try names("//b/following::*") == ["a", "d", "e"])
    }

    @Test("preceding axis selects nodes before the context, excluding ancestors")
    func test_preceding() throws {
        #expect(try names("/root/e/preceding::*") == ["a", "b", "c", "a", "d"])
    }

    @Test("self axis keeps the context node")
    func test_self() throws {
        #expect(try names("//c/self::c") == ["c"])
    }

    @Test("descendant-or-self powers the // abbreviation")
    func test_descendantOrSelf() throws {
        #expect(try names("/root/a/descendant-or-self::*") == ["a", "b", "c", "a", "d"])
    }

    @Test("attribute axis selects attributes")
    func test_attribute() throws {
        #expect(try names("/root/a/attribute::id") == ["id", "id"])
        #expect(try names("/root/a/@*") == ["id", "id"])
    }

    @Test("namespace declarations are not on the attribute axis")
    func test_attributeExcludesNamespaceDeclaration() throws {
        #expect(try names("/root/attribute::*").isEmpty)
    }

    @Test("namespace axis surfaces in-scope namespace nodes")
    func test_namespace() throws {
        let nodes = try PureXML.XPath.Query("/root/namespace::*").evaluate(over: doc())
        let uris = nodes.map(\.stringValue).sorted()
        #expect(uris.contains("urn:k"))
        #expect(uris.contains("http://www.w3.org/XML/1998/namespace"))
    }

    @Test("Results come back in document order regardless of axis direction")
    func test_documentOrder() throws {
        // ancestor axis is reverse, but the returned node-set is document-ordered.
        #expect(try names("//c/ancestor-or-self::node()") == ["root", "a", "b", "c"])
    }

    @Test("Whitespace is allowed around the :: axis separator")
    func test_whitespaceAroundAxisSeparator() throws {
        // XPath 1.0 allows whitespace between tokens, so `child :: a` is the
        // child axis with node test `a`, the same as `child::a` (Apache Xalan
        // select16, select27, select28).
        #expect(try names("/root/child::a") == ["a", "a"])
        #expect(try names("/root/child :: a") == ["a", "a"])
        #expect(try names("/root/descendant :: c") == ["c"])
    }
}
