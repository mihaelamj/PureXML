import Testing
@testable import PureXML

@Suite("DTD validation")
struct DTDValidationTests {
    private func issues(_ xml: String, strict: Bool = false) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.validateAgainstInternalDTD(xml, strict: strict)
    }

    @Test("EMPTY element accepts no content and rejects content")
    func test_empty() throws {
        try #expect(issues("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r/>").isEmpty)
        try #expect(!issues("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r>x</r>").isEmpty)
        try #expect(!issues("<!DOCTYPE r [<!ELEMENT r EMPTY><!ELEMENT a EMPTY>]><r><a/></r>").isEmpty)
    }

    @Test("(#PCDATA) accepts text and rejects child elements")
    func test_pcdata() throws {
        try #expect(issues("<!DOCTYPE r [<!ELEMENT r (#PCDATA)>]><r>hello</r>").isEmpty)
        try #expect(!issues("<!DOCTYPE r [<!ELEMENT r (#PCDATA)><!ELEMENT a EMPTY>]><r><a/></r>").isEmpty)
    }

    @Test("Sequence content model enforces order and presence")
    func test_sequence() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r (a,b)><!ELEMENT a EMPTY><!ELEMENT b EMPTY>]>"
        try #expect(issues("\(dtd)<r><a/><b/></r>").isEmpty)
        try #expect(!issues("\(dtd)<r><b/><a/></r>").isEmpty)
        try #expect(!issues("\(dtd)<r><a/></r>").isEmpty)
    }

    @Test("Choice content model accepts exactly one alternative")
    func test_choice() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r (a|b)><!ELEMENT a EMPTY><!ELEMENT b EMPTY>]>"
        try #expect(issues("\(dtd)<r><a/></r>").isEmpty)
        try #expect(issues("\(dtd)<r><b/></r>").isEmpty)
        try #expect(!issues("\(dtd)<r><a/><b/></r>").isEmpty)
    }

    @Test("Occurrence indicators bound repetition")
    func test_occurrence() throws {
        let star = "<!DOCTYPE r [<!ELEMENT r (a)*><!ELEMENT a EMPTY>]>"
        try #expect(issues("\(star)<r></r>").isEmpty)
        try #expect(issues("\(star)<r><a/><a/><a/></r>").isEmpty)
        let plus = "<!DOCTYPE r [<!ELEMENT r (a)+><!ELEMENT a EMPTY>]>"
        try #expect(!issues("\(plus)<r></r>").isEmpty)
        let optional = "<!DOCTYPE r [<!ELEMENT r (a?,b)><!ELEMENT a EMPTY><!ELEMENT b EMPTY>]>"
        try #expect(issues("\(optional)<r><b/></r>").isEmpty)
    }

    @Test("Mixed content allows only the declared elements")
    func test_mixed() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r (#PCDATA|a)*><!ELEMENT a EMPTY><!ELEMENT b EMPTY>]>"
        try #expect(issues("\(dtd)<r>text<a/>more</r>").isEmpty)
        try #expect(!issues("\(dtd)<r><b/></r>").isEmpty)
    }

    @Test("Element content rejects character data")
    func test_elementContentRejectsText() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r (a)><!ELEMENT a EMPTY>]>"
        try #expect(!issues("\(dtd)<r>text<a/></r>").isEmpty)
    }

    @Test("Strict mode rejects undeclared elements")
    func test_strictUndeclared() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r ANY>]>"
        try #expect(issues("\(dtd)<r><undeclared/></r>", strict: false).isEmpty)
        try #expect(!issues("\(dtd)<r><undeclared/></r>", strict: true).isEmpty)
    }

    @Test("A document without a DTD reports no content-model issues")
    func test_noDTD() throws {
        try #expect(issues("<r><a/></r>").isEmpty)
    }

    @Test("A content-model violation is located by coding path")
    func test_violationCarriesPath() throws {
        let dtd = "<!DOCTYPE r [<!ELEMENT r (a)><!ELEMENT a EMPTY>]>"
        let found = try issues("\(dtd)<r><a>oops</a></r>")
        #expect(found.count == 1)
        #expect(String(describing: found[0]) == "element <a> is declared EMPTY but has content at path: r/a")
    }
}
