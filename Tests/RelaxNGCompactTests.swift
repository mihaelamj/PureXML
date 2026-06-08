@testable import PureXML
import Testing

@Suite("RELAX NG compact syntax and references")
struct RelaxNGCompactTests {
    private func validCompact(
        _ rnc: String,
        _ xml: String,
        loader: @escaping (String) -> String? = { _ in nil },
    ) throws -> Bool {
        try PureXML.Schema.RelaxNG(compact: rnc, schemaLoader: loader).validate(xml)
    }

    @Test("A compact element with text content")
    func test_elementText() throws {
        let rnc = "element greeting { text }"
        #expect(try validCompact(rnc, "<greeting>hello</greeting>"))
        #expect(try !validCompact(rnc, "<other>hello</other>"))
        #expect(try !validCompact(rnc, "<greeting><child/></greeting>"))
    }

    @Test("A compact sequence of children in order")
    func test_sequence() throws {
        let rnc = """
        element book {
          element title { text },
          element author { text }
        }
        """
        #expect(try validCompact(rnc, "<book><title>T</title><author>A</author></book>"))
        #expect(try !validCompact(rnc, "<book><author>A</author><title>T</title></book>"))
    }

    @Test("Compact choice and cardinality")
    func test_choiceAndCardinality() throws {
        let rnc = """
        element list {
          (element a { text } | element b { text })*
        }
        """
        #expect(try validCompact(rnc, "<list><a>1</a><b>2</b><a>3</a></list>"))
        #expect(try validCompact(rnc, "<list></list>"))
        #expect(try !validCompact(rnc, "<list><c>x</c></list>"))
    }

    @Test("Compact attributes and grammar definitions")
    func test_grammarAndAttributes() throws {
        let rnc = """
        start = element root { item+ }
        item = element item { attribute id { text }, text }
        """
        #expect(try validCompact(rnc, "<root><item id=\"1\">a</item><item id=\"2\">b</item></root>"))
        #expect(try !validCompact(rnc, "<root><item>a</item></root>"))
        #expect(try !validCompact(rnc, "<root></root>"))
    }

    @Test("Compact include merges an external grammar's definitions")
    func test_include() throws {
        let library = "shared = element shared { text }"
        let main = """
        include "lib.rnc"
        start = element root { shared }
        """
        let loader: (String) -> String? = { $0 == "lib.rnc" ? library : nil }
        #expect(try validCompact(main, "<root><shared>x</shared></root>", loader: loader))
        #expect(try !validCompact(main, "<root><other>x</other></root>", loader: loader))
    }

    @Test("XML-syntax externalRef pulls in an external pattern")
    func test_externalRef() throws {
        let rng = "xmlns=\"http://relaxng.org/ns/structure/1.0\""
        let external = "<element name=\"note\" \(rng)><text/></element>"
        let main = "<externalRef href=\"note.rng\" \(rng)/>"
        let schema = try PureXML.Schema.RelaxNG(main, schemaLoader: { $0 == "note.rng" ? external : nil })
        #expect(try schema.validate("<note>hi</note>"))
        #expect(try !schema.validate("<other>hi</other>"))
    }
}
