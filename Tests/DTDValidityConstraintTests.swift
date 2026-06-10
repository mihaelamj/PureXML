@testable import PureXML
import Testing

/// The validity constraints added with the Sun-section burn-down: declaration-
/// level checks (reported at the document root), the root/DOCTYPE name match,
/// lexical checks on the ID family, CDATA as character data in element
/// content, and the strict-mode every-attribute-declared rule.
@Suite("DTD validity constraints")
struct DTDValidityConstraintTests {
    private func errors(_ xml: String, strict: Bool = false) throws -> [String] {
        try PureXML.validateAgainstInternalDTD(xml, strict: strict).map(\.reason)
    }

    @Test("The root element must match the DOCTYPE name")
    func test_rootElementType() throws {
        let xml = "<!DOCTYPE expected [<!ELEMENT expected EMPTY><!ELEMENT other EMPTY>]>\n<other/>"
        #expect(try errors(xml).contains { $0.contains("does not match the DOCTYPE name") })
        let matching = "<!DOCTYPE expected [<!ELEMENT expected EMPTY>]>\n<expected/>"
        #expect(try errors(matching).isEmpty)
    }

    @Test("An element type declared twice is reported")
    func test_uniqueElementDeclaration() throws {
        let xml = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ELEMENT x (#PCDATA)><!ELEMENT x (#PCDATA)>]>\n<r/>"
        #expect(try errors(xml).contains { $0.contains("declared more than once") })
    }

    @Test("Declaration findings carry the declaration's coding path")
    func test_findingsAreLocated() throws {
        let xml = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ELEMENT x (#PCDATA)><!ELEMENT x (#PCDATA)><!ATTLIST r a (one|one) #IMPLIED>]>\n<r/>"
        let rendered = try PureXML.validateAgainstInternalDTD(xml).map { String(describing: $0) }
        #expect(rendered.contains { $0.hasSuffix("at path: x") })
        #expect(rendered.contains { $0.hasSuffix("at path: r/@a") })
        #expect(!rendered.contains { $0.contains("at root of document") })
    }

    @Test("Mixed content may not repeat a name")
    func test_mixedDuplicates() throws {
        let xml = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ELEMENT y (#PCDATA|x|x)*>]>\n<r/>"
        #expect(try errors(xml).contains { $0.contains("repeats 'x'") })
    }

    @Test("An element type may declare at most one ID attribute")
    func test_oneIDPerElement() throws {
        let xml = """
        <!DOCTYPE r [<!ELEMENT r EMPTY>
        <!ATTLIST r a ID #IMPLIED b ID #IMPLIED>]>
        <r/>
        """
        #expect(try errors(xml).contains { $0.contains("more than one ID attribute") })
    }

    @Test("NOTATION lists and NDATA entities must name declared notations")
    func test_notationsDeclared() throws {
        let list = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r t NOTATION (a|b) #IMPLIED><!NOTATION a SYSTEM \"x\">]>\n<r/>"
        #expect(try errors(list).contains { $0.contains("lists undeclared notation 'b'") })
        let ndata = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ENTITY e SYSTEM \"u\" NDATA missing>]>\n<r/>"
        #expect(try errors(ndata).contains { $0.contains("names undeclared notation 'missing'") })
    }

    @Test("Attribute defaults must be legal for their type, and IDs default-free")
    func test_attributeDefaultLegal() throws {
        let id = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r a ID \"x\">]>\n<r/>"
        #expect(try errors(id).contains { $0.contains("must be #IMPLIED or #REQUIRED") })
        let idref = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r a IDREF \"42\">]>\n<r/>"
        #expect(try errors(idref).contains { $0.contains("IDREF default") })
        let nmtokens = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r a NMTOKENS \"alpha $beta\">]>\n<r/>"
        #expect(try errors(nmtokens).contains { $0.contains("NMTOKENS default") })
        let entities = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r a ENTITIES \"ok 2bad\">]>\n<r/>"
        #expect(try errors(entities).contains { $0.contains("ENTITIES default") })
        let enumerated = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r a (x|y) \"z\">]>\n<r/>"
        #expect(try errors(enumerated).contains { $0.contains("outside its enumeration") })
    }

    @Test("ID and IDREF values must be lexical Names")
    func test_idLexicalForm() throws {
        let xml = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r id ID #IMPLIED>]>\n<r id=\"42a\"/>"
        #expect(try errors(xml).contains { $0.contains("not a valid ID") })
    }

    @Test("A CDATA section is character data in element content")
    func test_cdataInElementContent() throws {
        let xml = "<!DOCTYPE r [<!ELEMENT r (a)><!ELEMENT a EMPTY>]>\n<r><a/><![CDATA[]]></r>"
        #expect(try errors(xml).contains { $0.contains("contains character data") })
    }

    @Test("Strict mode requires every attribute to be declared")
    func test_undeclaredAttribute() throws {
        let xml = "<!DOCTYPE r [<!ELEMENT r EMPTY>]>\n<r xml:space=\"preserve\"/>"
        #expect(try errors(xml, strict: true).contains { $0.contains("is not declared") })
        #expect(try errors(xml).isEmpty)
    }
}
