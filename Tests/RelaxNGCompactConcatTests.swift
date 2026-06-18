import Testing
@testable import PureXML

@Suite("RELAX NG compact string concatenation")
struct RelaxNGCompactConcatTests {
    private func validRNC(_ rnc: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(compact: rnc).validate(xml)
    }

    @Test("A value literal split with ~ is concatenated")
    func test_valueConcatenation() throws {
        let rnc = "element greeting { \"hello \" ~ \"world\" }"
        #expect(try validRNC(rnc, "<greeting>hello world</greeting>"))
        #expect(try !validRNC(rnc, "<greeting>hello</greeting>"))
    }

    @Test("More than two segments concatenate left to right")
    func test_multiSegment() throws {
        let rnc = "element n { \"a\" ~ \"b\" ~ \"c\" }"
        #expect(try validRNC(rnc, "<n>abc</n>"))
        #expect(try !validRNC(rnc, "<n>ab</n>"))
    }

    @Test("A namespace URI may be assembled with ~")
    func test_namespaceConcatenation() throws {
        let rnc = """
        namespace p = "urn:" ~ "example"
        element root { element p:item { empty } }
        """
        #expect(try validRNC(rnc, "<root xmlns:p=\"urn:example\"><p:item/></root>"))
        #expect(try !validRNC(rnc, "<root xmlns:p=\"urn:other\"><p:item/></root>"))
    }
}
