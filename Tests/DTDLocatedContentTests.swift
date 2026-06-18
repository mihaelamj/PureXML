import Testing
@testable import PureXML

@Suite("DTD located content-model errors")
struct DTDLocatedContentTests {
    private func reasons(_ xml: String) throws -> [String] {
        try PureXML.validateAgainstInternalDTD(xml).map(\.reason)
    }

    @Test("A stray child outside the model is named individually")
    func test_strayChild() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r (a, b)><!ELEMENT a EMPTY><!ELEMENT b EMPTY><!ELEMENT x EMPTY>]>"
        let found = try reasons("\(dtd)<r><a/><x/></r>")
        #expect(found.contains { $0.contains("<x>") && $0.contains("not allowed in <r>") })
    }

    @Test("Two distinct stray children are each reported (recovery)")
    func test_multipleStray() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r (a)><!ELEMENT a EMPTY><!ELEMENT x EMPTY><!ELEMENT y EMPTY>]>"
        let found = try reasons("\(dtd)<r><x/><y/></r>")
        #expect(found.contains { $0.contains("<x>") })
        #expect(found.contains { $0.contains("<y>") })
    }

    @Test("An ordering-only violation lists the allowed elements as a hint")
    func test_orderingHint() throws {
        // Both children are in the alphabet, but reversed against (a, b).
        let dtd = "<!DOCTYPE r [<!ELEMENT r (a, b)><!ELEMENT a EMPTY><!ELEMENT b EMPTY>]>"
        let found = try reasons("\(dtd)<r><b/><a/></r>")
        #expect(found.contains { $0.contains("do not match its content model") && $0.contains("<a>") && $0.contains("<b>") })
    }

    @Test("A conforming document has no content errors")
    func test_valid() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r (a, b)><!ELEMENT a EMPTY><!ELEMENT b EMPTY>]>"
        #expect(try reasons("\(dtd)<r><a/><b/></r>").isEmpty)
    }
}
