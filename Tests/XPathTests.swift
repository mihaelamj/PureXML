@testable import PureXML
import Testing

@Suite("XPath")
struct XPathTests {
    private func catalog() throws -> PureXML.Model.Node {
        try PureXML.parse(
            "<catalog>"
                + "<book id=\"bk101\" lang=\"en\"><title>XML Guide</title><author>Drobnik</author></book>"
                + "<book id=\"bk102\"><title>YAML Guide</title></book>"
                + "<magazine><title>Wired</title></magazine>"
                + "</catalog>",
        )
    }

    @Test("Absolute child path selects matching elements")
    func test_childPath() throws {
        let books = try PureXML.XPath.Query("/catalog/book").elements(over: catalog())
        #expect(books.count == 2)
        #expect(books.first?.attributes.first?.value == "bk101")
    }

    @Test("Descendant path finds nodes at any depth")
    func test_descendantPath() throws {
        let titles = try PureXML.XPath.Query("//title").strings(over: catalog())
        #expect(titles == ["XML Guide", "YAML Guide", "Wired"])
    }

    @Test("Positional predicate selects within the parent")
    func test_positionPredicate() throws {
        let titles = try PureXML.XPath.Query("/catalog/book[1]/title").strings(over: catalog())
        #expect(titles == ["XML Guide"])
    }

    @Test("Attribute-equality predicate filters elements")
    func test_attributeEqualityPredicate() throws {
        let titles = try PureXML.XPath.Query("//book[@id='bk102']/title").strings(over: catalog())
        #expect(titles == ["YAML Guide"])
    }

    @Test("Attribute step selects attributes")
    func test_attributeStep() throws {
        let selections = try PureXML.XPath.Query("/catalog/book/@id").evaluate(over: catalog())
        #expect(selections.map(\.stringValue) == ["bk101", "bk102"])
        if case .attribute = selections.first {} else {
            Issue.record("expected an attribute selection")
        }
    }

    @Test("Attribute-existence predicate filters elements")
    func test_attributeExistencePredicate() throws {
        let books = try PureXML.XPath.Query("//book[@lang]").elements(over: catalog())
        #expect(books.count == 1)
        #expect(books.first?.attributes.first?.value == "bk101")
    }

    @Test("Wildcard selects all child elements")
    func test_wildcard() throws {
        let children = try PureXML.XPath.Query("/catalog/*").elements(over: catalog())
        #expect(children.count == 3)
    }

    @Test("Child-equality predicate filters by child string value")
    func test_childEqualityPredicate() throws {
        let books = try PureXML.XPath.Query("//book[title='YAML Guide']").elements(over: catalog())
        #expect(books.count == 1)
        #expect(books.first?.attributes.first?.value == "bk102")
    }

    @Test("text() selects character data")
    func test_textNodeTest() throws {
        let strings = try PureXML.XPath.Query("//author/text()").strings(over: catalog())
        #expect(strings == ["Drobnik"])
    }

    @Test("The top-level convenience evaluates a path")
    func test_topLevelConvenience() throws {
        let selections = try PureXML.xpath("//magazine/title", over: catalog())
        #expect(selections.map(\.stringValue) == ["Wired"])
    }

    @Test("Unsupported upward axis is rejected at compile time")
    func test_unsupportedAxis() {
        #expect(throws: PureXML.XPath.QueryError.self) {
            _ = try PureXML.XPath.Query("/catalog/..")
        }
    }

    @Test("An empty path is rejected")
    func test_emptyPath() {
        #expect(throws: PureXML.XPath.QueryError.empty) {
            _ = try PureXML.XPath.Query("   ")
        }
    }
}
