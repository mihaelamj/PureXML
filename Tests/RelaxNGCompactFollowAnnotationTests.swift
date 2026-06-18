import Testing
@testable import PureXML

@Suite("RELAX NG compact >> follow-annotations")
struct RelaxNGCompactFollowAnnotationTests {
    private func valid(_ rnc: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(compact: rnc).validate(xml)
    }

    @Test("A follow-annotation after an element is ignored")
    func test_afterElement() throws {
        let rnc = "element root { element a { empty } >> a:documentation [ \"a child\" ] }"
        #expect(try valid(rnc, "<root><a/></root>"))
        #expect(try !valid(rnc, "<root><b/></root>"))
    }

    @Test("A follow-annotation on a define's pattern is ignored")
    func test_onDefine() throws {
        let rnc = """
        start = element root { ref-a }
        ref-a = element a { empty } >> a:doc [ "the a element" ]
        """
        #expect(try valid(rnc, "<root><a/></root>"))
    }

    @Test("Follow-annotations chain after a particle")
    func test_chained() throws {
        let rnc = "element root { element a { empty } >> a:x [ \"1\" ] >> a:y [ \"2\" ], element b { empty } }"
        #expect(try valid(rnc, "<root><a/><b/></root>"))
        #expect(try !valid(rnc, "<root><a/></root>"))
    }

    @Test("A leading and a follow annotation can both appear")
    func test_leadingAndFollow() throws {
        let rnc = "element root { [ a:doc [ \"lead\" ] ] element a { empty } >> a:doc [ \"follow\" ] }"
        #expect(try valid(rnc, "<root><a/></root>"))
    }
}
