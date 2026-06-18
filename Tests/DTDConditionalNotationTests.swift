import Testing
@testable import PureXML

@Suite("DTD conditional sections, notations, NDATA")
struct DTDConditionalNotationTests {
    private let dtdAllowed = PureXML.Parsing.Limits(allowDoctype: true)

    private func documentType(_ xml: String, resolver: PureXML.Parsing.EntityResolver = .refusing) throws -> PureXML.Parsing.DocumentType {
        try PureXML.Parsing.Parser().parseWithDocumentType(xml, limits: dtdAllowed, resolver: resolver).documentType
    }

    private func validate(_ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.validateAgainstInternalDTD(xml)
    }

    // MARK: Conditional sections

    @Test("An INCLUDE conditional section's declarations take effect")
    func test_includeSection() throws {
        let xml = "<!DOCTYPE r [<![INCLUDE[<!ELEMENT r EMPTY>]]>]><r/>"
        let type = try documentType(xml)
        #expect(type.elementModels["r"] != nil)
    }

    @Test("An IGNORE conditional section's declarations are discarded")
    func test_ignoreSection() throws {
        let xml = "<!DOCTYPE r [<![IGNORE[<!ELEMENT r EMPTY>]]>]><r/>"
        let type = try documentType(xml)
        #expect(type.elementModels["r"] == nil)
    }

    @Test("A parameter-entity keyword selects the conditional section")
    func test_conditionalKeywordFromParameterEntity() throws {
        let xml = "<!DOCTYPE r [<!ENTITY % draft \"INCLUDE\"><![%draft;[<!ELEMENT r EMPTY>]]>]><r/>"
        let type = try documentType(xml)
        #expect(type.elementModels["r"] != nil)
    }

    @Test("A nested IGNORE inside an INCLUDE is honored")
    func test_nestedConditional() throws {
        let xml = "<!DOCTYPE r [<![INCLUDE[<!ELEMENT r EMPTY><![IGNORE[<!ELEMENT skip EMPTY>]]>]]>]><r/>"
        let type = try documentType(xml)
        #expect(type.elementModels["r"] != nil)
        #expect(type.elementModels["skip"] == nil)
    }

    // MARK: Notations and NDATA

    @Test("A <!NOTATION> declaration is parsed and stored")
    func test_notationStored() throws {
        let xml = "<!DOCTYPE r [<!NOTATION gif SYSTEM \"image/gif\">]><r/>"
        let type = try documentType(xml)
        #expect(type.notations["gif"]?.systemID == "image/gif")
    }

    @Test("An NDATA unparsed entity records its notation")
    func test_unparsedEntity() throws {
        let xml = "<!DOCTYPE r [<!NOTATION gif SYSTEM \"g\"><!ENTITY logo SYSTEM \"l.gif\" NDATA gif>]><r/>"
        let type = try documentType(xml)
        #expect(type.unparsedEntities["logo"]?.notation == "gif")
        #expect(type.unparsedEntities["logo"]?.id.systemID == "l.gif")
        // An unparsed entity is not a general entity.
        #expect(type.entities["logo"] == nil)
    }

    // MARK: External parameter entities

    @Test("An external parameter entity is loaded only through a resolver")
    func test_externalParameterEntity() throws {
        let xml = "<!DOCTYPE r [<!ENTITY % ext SYSTEM \"ext.dtd\">%ext;]><r/>"
        // Refused by default: the external parameter entity is not loaded.
        #expect(try documentType(xml).elementModels["r"] == nil)
        // With a resolver, its declarations take effect.
        let resolver = PureXML.Parsing.EntityResolver(resolveExternalSubset: { _ in "<!ELEMENT r EMPTY>" })
        #expect(try documentType(xml, resolver: resolver).elementModels["r"] != nil)
    }

    // MARK: NOTATION attribute validation

    @Test("A NOTATION attribute value must be a declared, listed notation")
    func test_notationAttribute() throws {
        let dtd = "<!NOTATION gif SYSTEM \"g\"><!NOTATION png SYSTEM \"p\"><!ATTLIST r kind NOTATION (gif|png) #IMPLIED>"
        #expect(try validate("<!DOCTYPE r [\(dtd)]><r kind=\"gif\"/>").isEmpty)
        // A value outside the declaration's list fails.
        #expect(try !validate("<!DOCTYPE r [\(dtd)]><r kind=\"jpg\"/>").isEmpty)
    }

    @Test("A NOTATION attribute listing an undeclared notation fails")
    func test_notationAttributeUndeclared() throws {
        // 'bmp' is listed in the ATTLIST but never declared with <!NOTATION>.
        let dtd = "<!ATTLIST r kind NOTATION (bmp) #IMPLIED>"
        #expect(try !validate("<!DOCTYPE r [\(dtd)]><r kind=\"bmp\"/>").isEmpty)
    }
}
