import Testing
@testable import PureXML

@Suite("RELAX NG compact name-class subtraction")
struct RelaxNGNameClassTests {
    private func valid(_ rnc: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(compact: rnc).validate(xml)
    }

    @Test("* - name admits any element except the subtracted one")
    func test_subtraction() throws {
        let rnc = "element root { element * - skip { empty }* }"
        #expect(try valid(rnc, "<root><a/><b/></root>"))
        #expect(try !valid(rnc, "<root><skip/></root>"))
    }

    @Test("A plain wildcard still admits everything")
    func test_plainWildcard() throws {
        let rnc = "element root { element * { empty }* }"
        #expect(try valid(rnc, "<root><skip/><a/></root>"))
    }
}
