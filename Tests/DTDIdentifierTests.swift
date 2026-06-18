import Testing
@testable import PureXML

@Suite("DTD ID and IDREF validation")
struct DTDIdentifierTests {
    private func issues(_ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.validateAgainstInternalDTD(xml)
    }

    private let idDTD = "<!DOCTYPE root [<!ELEMENT root (item)*><!ELEMENT item EMPTY>"
        + "<!ATTLIST item id ID #IMPLIED ref IDREF #IMPLIED refs IDREFS #IMPLIED>]>"

    @Test("Unique IDs validate; duplicate IDs are rejected")
    func test_idUniqueness() throws {
        try #expect(issues("\(idDTD)<root><item id=\"a\"/><item id=\"b\"/></root>").isEmpty)
        try #expect(!issues("\(idDTD)<root><item id=\"a\"/><item id=\"a\"/></root>").isEmpty)
    }

    @Test("IDREF resolves to an ID anywhere in the document, including forward")
    func test_idrefForwardReference() throws {
        try #expect(issues("\(idDTD)<root><item ref=\"b\"/><item id=\"b\"/></root>").isEmpty)
    }

    @Test("A dangling IDREF is rejected")
    func test_danglingIdref() throws {
        try #expect(!issues("\(idDTD)<root><item ref=\"x\"/><item id=\"b\"/></root>").isEmpty)
    }

    @Test("IDREFS resolves each token; a dangling token is rejected")
    func test_idrefs() throws {
        let valid = "\(idDTD)<root><item id=\"a\"/><item id=\"b\"/><item refs=\"a b\"/></root>"
        try #expect(issues(valid).isEmpty)
        let dangling = "\(idDTD)<root><item id=\"a\"/><item refs=\"a z\"/></root>"
        try #expect(!issues(dangling).isEmpty)
    }
}
