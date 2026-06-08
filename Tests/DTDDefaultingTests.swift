@testable import PureXML
import Testing

@Suite("DTD attribute defaulting and tokenized types")
struct DTDDefaultingTests {
    private func validate(_ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.validateAgainstInternalDTD(xml)
    }

    private func attribute(_ element: PureXML.Model.Element?, _ name: String) -> String? {
        element?.attributes.first { $0.name.description == name }?.value
    }

    private func root(_ node: PureXML.Model.Node) -> PureXML.Model.Element? {
        guard case let .document(children) = node else { return nil }
        return children.compactMap(\.element).first
    }

    // MARK: Defaulting

    @Test("A default attribute value is injected into an element that omits it")
    func test_defaultInjected() throws {
        let xml = "<!DOCTYPE r [<!ATTLIST r kind CDATA \"box\">]><r/>"
        let node = try PureXML.parseApplyingInternalDTDDefaults(xml)
        #expect(attribute(root(node), "kind") == "box")
    }

    @Test("A present attribute is not overwritten by its default")
    func test_presentNotOverwritten() throws {
        let xml = "<!DOCTYPE r [<!ATTLIST r kind CDATA \"box\">]><r kind=\"crate\"/>"
        let node = try PureXML.parseApplyingInternalDTDDefaults(xml)
        #expect(attribute(root(node), "kind") == "crate")
    }

    @Test("A #FIXED value is injected when absent")
    func test_fixedInjected() throws {
        let xml = "<!DOCTYPE r [<!ATTLIST r v CDATA #FIXED \"1\">]><r/>"
        let node = try PureXML.parseApplyingInternalDTDDefaults(xml)
        #expect(attribute(root(node), "v") == "1")
    }

    @Test("#REQUIRED and #IMPLIED inject nothing")
    func test_requiredImpliedInjectNothing() throws {
        let xml = "<!DOCTYPE r [<!ATTLIST r a CDATA #REQUIRED b CDATA #IMPLIED>]><r a=\"x\"/>"
        let node = try PureXML.parseApplyingInternalDTDDefaults(xml)
        #expect(attribute(root(node), "b") == nil)
    }

    @Test("A non-CDATA default value is whitespace-normalized")
    func test_defaultNormalized() throws {
        let xml = "<!DOCTYPE r [<!ATTLIST r t NMTOKENS \"  a\tb  \">]><r/>"
        let node = try PureXML.parseApplyingInternalDTDDefaults(xml)
        // Tabs become spaces and the value is collapsed and trimmed.
        #expect(attribute(root(node), "t") == "a b")
    }

    @Test("A CDATA default keeps internal content but replaces tabs with spaces")
    func test_cdataDefaultReplaceOnly() throws {
        let xml = "<!DOCTYPE r [<!ATTLIST r t CDATA \"a\tb\">]><r/>"
        let node = try PureXML.parseApplyingInternalDTDDefaults(xml)
        #expect(attribute(root(node), "t") == "a b")
    }

    @Test("A character reference in a default is expanded")
    func test_defaultCharacterReference() throws {
        let xml = "<!DOCTYPE r [<!ATTLIST r t CDATA \"&#65;&#x42;\">]><r/>"
        let node = try PureXML.parseApplyingInternalDTDDefaults(xml)
        #expect(attribute(root(node), "t") == "AB")
    }

    // MARK: Tokenized type validation

    @Test("A valid NMTOKEN passes and an invalid one fails")
    func test_nmtoken() throws {
        let valid = "<!DOCTYPE r [<!ATTLIST r t NMTOKEN #IMPLIED>]><r t=\"a.b-c\"/>"
        #expect(try validate(valid).isEmpty)
        let bad = "<!DOCTYPE r [<!ATTLIST r t NMTOKEN #IMPLIED>]><r t=\"a b\"/>"
        #expect(try !validate(bad).isEmpty)
    }

    @Test("NMTOKENS requires every whitespace-separated token to be a name token")
    func test_nmtokens() throws {
        let valid = "<!DOCTYPE r [<!ATTLIST r t NMTOKENS #IMPLIED>]><r t=\"a b c\"/>"
        #expect(try validate(valid).isEmpty)
        let bad = "<!DOCTYPE r [<!ATTLIST r t NMTOKENS #IMPLIED>]><r t=\"a b@d\"/>"
        #expect(try !validate(bad).isEmpty)
    }

    @Test("ENTITY must name a declared unparsed entity")
    func test_entity() throws {
        let dtd = "<!NOTATION gif SYSTEM \"g\"><!ENTITY logo SYSTEM \"l.gif\" NDATA gif><!ATTLIST r t ENTITY #IMPLIED>"
        #expect(try validate("<!DOCTYPE r [\(dtd)]><r t=\"logo\"/>").isEmpty)
        // A syntactically valid name that is not a declared unparsed entity fails.
        #expect(try !validate("<!DOCTYPE r [\(dtd)]><r t=\"other\"/>").isEmpty)
    }

    @Test("ENTITIES requires every token to name a declared unparsed entity")
    func test_entities() throws {
        let dtd = "<!NOTATION gif SYSTEM \"g\"><!ENTITY a SYSTEM \"a.gif\" NDATA gif><!ENTITY b SYSTEM \"b.gif\" NDATA gif><!ATTLIST r t ENTITIES #IMPLIED>"
        #expect(try validate("<!DOCTYPE r [\(dtd)]><r t=\"a b\"/>").isEmpty)
        #expect(try !validate("<!DOCTYPE r [\(dtd)]><r t=\"a c\"/>").isEmpty)
    }
}
