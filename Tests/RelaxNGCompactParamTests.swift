import Testing
@testable import PureXML

@Suite("RELAX NG compact datatype parameter blocks")
struct RelaxNGCompactParamTests {
    private func valid(_ rnc: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(compact: rnc).validate(xml)
    }

    @Test("A minLength param block constrains a data value")
    func test_minLength() throws {
        let rnc = "element code { xsd:string { minLength = \"3\" } }"
        #expect(try valid(rnc, "<code>abc</code>"))
        #expect(try !valid(rnc, "<code>ab</code>"))
    }

    @Test("A maxInclusive param block constrains a numeric value")
    func test_maxInclusive() throws {
        let rnc = "element n { xsd:integer { maxInclusive = \"10\" } }"
        #expect(try valid(rnc, "<n>5</n>"))
        #expect(try !valid(rnc, "<n>20</n>"))
    }

    @Test("Multiple params in one block all apply")
    func test_multipleParams() throws {
        let rnc = "element code { xsd:string { minLength = \"2\" maxLength = \"4\" } }"
        #expect(try valid(rnc, "<code>abc</code>"))
        #expect(try !valid(rnc, "<code>a</code>"))
        #expect(try !valid(rnc, "<code>abcde</code>"))
    }

    @Test("A datatype with no param block still validates against its base")
    func test_noParams() throws {
        let rnc = "element n { xsd:integer }"
        #expect(try valid(rnc, "<n>42</n>"))
        #expect(try !valid(rnc, "<n>x</n>"))
    }
}
