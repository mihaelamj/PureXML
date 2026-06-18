import Testing
@testable import PureXML

/// The XML 1.0 errata behaviors from the eduni burn-down: 3.3.3 attribute-
/// value normalization, the lenient undeclared-entity path (production 68),
/// the E15 family (references and comments in EMPTY elements, character-
/// reference whitespace in element content), E2 duplicate enumeration
/// tokens, and E14 declarations completed inside PE replacements.
@Suite("XML errata validity")
struct ErrataValidityTests {
    private func limits() -> PureXML.Parsing.Limits {
        PureXML.Parsing.Limits(allowDoctype: true)
    }

    private func errors(_ xml: String, strict: Bool = false) throws -> [String] {
        try PureXML.validateAgainstInternalDTD(xml, strict: strict).map(\.reason)
    }

    @Test("Literal whitespace in attribute values normalizes to spaces; character references survive")
    func test_attributeValueNormalization() throws {
        let node = try PureXML.parse("<a b=\"1\n2\t3\" c=\"x&#9;y\"/>")
        guard case let .document(children) = node, case let .element(element)? = children.first else {
            Issue.record("no element")
            return
        }
        #expect(element.attributes[0].value == "1 2 3")
        #expect(element.attributes[1].value == "x\ty")
    }

    @Test("With an unread external subset, an undeclared entity is a finding, not a fatal error")
    func test_lenientUndeclaredEntity() throws {
        let xml = "<!DOCTYPE r SYSTEM \"x.dtd\" [<!ELEMENT r ANY>]>\n<r>&mystery;</r>"
        let found = try errors(xml)
        #expect(found.contains { $0.contains("'&mystery;' is referenced but not declared") })
        // Without any external declarations possible it stays fatal.
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse("<!DOCTYPE r [<!ELEMENT r ANY>]>\n<r>&mystery;</r>", limits: limits())
        }
    }

    @Test("E15: references, comments, and whitespace are content for EMPTY elements")
    func test_emptyElementContent() throws {
        let reference = "<!DOCTYPE f [<!ELEMENT f EMPTY><!ENTITY empty \"\">]>\n<f>&empty;</f>"
        #expect(try !errors(reference).isEmpty)
        let comment = "<!DOCTYPE f [<!ELEMENT f EMPTY>]>\n<f><!-- c --></f>"
        #expect(try !errors(comment).isEmpty)
        let whitespace = "<!DOCTYPE f [<!ELEMENT f EMPTY>]>\n<f> </f>"
        #expect(try !errors(whitespace).isEmpty)
        let clean = "<!DOCTYPE f [<!ELEMENT f EMPTY>]>\n<f/>"
        #expect(try errors(clean).isEmpty)
    }

    @Test("E15: character-reference whitespace is data in element content; entity whitespace is not")
    func test_elementContentWhitespace() throws {
        let charRef = "<!DOCTYPE f [<!ELEMENT f (f*)>]>\n<f><f/>&#32;<f/></f>"
        #expect(try !errors(charRef).isEmpty)
        let viaEntity = "<!DOCTYPE f [<!ELEMENT f (f*)><!ENTITY s \" \">]>\n<f><f/>&s;<f/></f>"
        #expect(try errors(viaEntity).isEmpty)
        let doubleEscape = "<!DOCTYPE f [<!ELEMENT f (f*)><!ENTITY s \"&#38;#32;\">]>\n<f><f/>&s;<f/></f>"
        #expect(try !errors(doubleEscape).isEmpty)
    }

    @Test("E2: duplicate tokens in enumerated and NOTATION lists are reported")
    func test_duplicateEnumerationTokens() throws {
        let xml = "<!DOCTYPE f [<!ELEMENT f ANY><!ATTLIST f bar (one|one) #IMPLIED>]>\n<f/>"
        #expect(try errors(xml).contains { $0.contains("repeats the token 'one'") })
    }

    @Test("E14: a declaration completed inside a PE replacement parses and reports the VC")
    func test_declarationPENesting() throws {
        let dtd = "<!ELEMENT foo ANY>\n<!ENTITY % e \"bar CDATA #IMPLIED>\">\n<!ATTLIST foo %e;\n"
        let xml = "<!DOCTYPE foo SYSTEM \"x.dtd\">\n<foo/>"
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, _ in nil },
            resolveExternalSubset: { _ in dtd },
        )
        let found = try PureXML.validateAgainstInternalDTD(xml, resolver: resolver).map(\.reason)
        #expect(found.contains { $0.contains("Proper Declaration/PE Nesting") })
    }
}
