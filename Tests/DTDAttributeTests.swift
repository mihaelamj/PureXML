@testable import PureXML
import Testing

@Suite("DTD attribute validation")
struct DTDAttributeTests {
    private func issues(_ xml: String, strict: Bool = false) throws -> [PureXML.Validation.Issue] {
        try PureXML.validateAgainstInternalDTD(xml, strict: strict)
    }

    @Test("#REQUIRED attribute must be present")
    func test_required() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r id CDATA #REQUIRED>]>"
        try #expect(issues("\(dtd)<r id=\"x\"/>").isEmpty)
        try #expect(!issues("\(dtd)<r/>").isEmpty)
    }

    @Test("#FIXED attribute must match when present and may be omitted")
    func test_fixed() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r v CDATA #FIXED \"1\">]>"
        try #expect(issues("\(dtd)<r v=\"1\"/>").isEmpty)
        try #expect(issues("\(dtd)<r/>").isEmpty)
        try #expect(!issues("\(dtd)<r v=\"2\"/>").isEmpty)
    }

    @Test("Enumerated attribute must take a listed value")
    func test_enumeration() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r dir (ltr|rtl) #IMPLIED>]>"
        try #expect(issues("\(dtd)<r dir=\"ltr\"/>").isEmpty)
        try #expect(issues("\(dtd)<r/>").isEmpty)
        try #expect(!issues("\(dtd)<r dir=\"up\"/>").isEmpty)
    }

    @Test("Multiple attributes in one ATTLIST are each checked")
    func test_multipleAttributes() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r a CDATA #REQUIRED b (x|y) #IMPLIED>]>"
        try #expect(issues("\(dtd)<r a=\"1\" b=\"x\"/>").isEmpty)
        // a is missing and b is out of its enumeration: two violations.
        try #expect(issues("\(dtd)<r b=\"z\"/>").count == 2)
    }

    @Test("Tokenized types (ID) do not constrain the value")
    func test_idTypeUnconstrained() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r id ID #REQUIRED>]>"
        try #expect(issues("\(dtd)<r id=\"anything\"/>").isEmpty)
    }
}
