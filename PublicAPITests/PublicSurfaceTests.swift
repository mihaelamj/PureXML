// Deliberately NOT @testable: these tests compile against the public
// surface exactly as an external package would, so a public facade over
// internal members (the #142 class of gap: a public EventReader whose
// next() was internal) fails CI instead of hiding behind testability.
import PureXML
import Testing

@Suite("Public API surface")
struct PublicSurfaceTests {
    @Test("Parse, query, and serialize work through the public surface")
    func test_parseQuerySerialize() throws {
        let document = try PureXML.parse("<r><a k=\"v\">x</a><a>y</a></r>")
        let query = try PureXML.XPath.Query("count(//a)")
        #expect(try query.number(over: document) == 2)
        #expect(PureXML.serialize(document).contains("<a k=\"v\">x</a>"))
    }

    @Test("The streaming reader pulls events publicly, bounded memory")
    func test_streamingPull() throws {
        var reader = PureXML.events("<r><a>x</a><!--c--></r>")
        var names: [String] = []
        var texts: [String] = []
        var comments = 0
        while let event = try reader.next() {
            switch event {
            case let .startElement(name, _): names.append(name.description)
            case let .characters(text): texts.append(text)
            case .comment: comments += 1
            default: break
            }
        }
        #expect(names == ["r", "a"])
        #expect(texts == ["x"])
        #expect(comments == 1)
    }

    @Test("The streaming reader accepts a chunked pull source")
    func test_streamingFromChunks() throws {
        var chunks = ["<r><a>", "hello", "</a></r>"].makeIterator()
        var characters: [Character] = []
        var reader = PureXML.Parsing.EventReader(pulling: {
            if characters.isEmpty, let chunk = chunks.next() { characters = Array(chunk) }
            return characters.isEmpty ? nil : characters.removeFirst()
        })
        var events = 0
        while try reader.next() != nil {
            events += 1
        }
        #expect(events == 5)
    }

    @Test("An evaluation budget throws instead of evaluating unbounded")
    func test_evaluationBudget() throws {
        let tree = try PureXML.parseTree("<r><a/><a/><a/><a/><a/></r>")
        let query = try PureXML.XPath.Query("//a")
        // Unbounded evaluates; a budget below the result size throws.
        #expect(try query.value(at: tree).nodes?.count == 5)
        #expect(throws: PureXML.XPath.QueryError.budgetExceeded(3)) {
            _ = try query.value(at: tree, budget: .init(maxNodeSetLength: 3))
        }
        // The libxml2-compatible cap admits ordinary documents.
        #expect(try query.value(at: tree, budget: .libxml2Compatible).nodes?.count == 5)
    }
}
