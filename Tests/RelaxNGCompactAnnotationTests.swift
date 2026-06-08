@testable import PureXML
import Testing

@Suite("RELAX NG compact annotations and div grouping")
struct RelaxNGCompactAnnotationTests {
    private func valid(_ rnc: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(compact: rnc).validate(xml)
    }

    @Test("A leading annotation on a define is ignored")
    func test_annotationOnDefine() throws {
        let rnc = """
        [ a:documentation [ "the root element" ] ]
        start = element root { text }
        """
        #expect(try valid(rnc, "<root>hello</root>"))
        #expect(try !valid(rnc, "<other>hello</other>"))
    }

    @Test("An annotation before a pattern is ignored")
    func test_annotationOnPattern() throws {
        let rnc = "element root { [ a:doc \"a child\" ] element child { text } }"
        #expect(try valid(rnc, "<root><child>x</child></root>"))
        #expect(try !valid(rnc, "<root><wrong>x</wrong></root>"))
    }

    @Test("A div grouping contributes its defines transparently")
    func test_divGrouping() throws {
        let rnc = """
        start = element root { ref-a, ref-b }
        div {
          ref-a = element a { empty }
          ref-b = element b { empty }
        }
        """
        #expect(try valid(rnc, "<root><a/><b/></root>"))
        #expect(try !valid(rnc, "<root><a/></root>"))
    }

    @Test("A div may carry its own annotation and nest")
    func test_divAnnotatedNested() throws {
        let rnc = """
        start = element root { ref-a }
        [ a:doc "a section" ]
        div {
          div {
            ref-a = element a { empty }
          }
        }
        """
        #expect(try valid(rnc, "<root><a/></root>"))
    }

    @Test("A define literally named div still works when assigned")
    func test_defineNamedDiv() throws {
        let rnc = """
        start = element root { div }
        div = element section { empty }
        """
        #expect(try valid(rnc, "<root><section/></root>"))
    }
}
