@testable import PureXML
import Testing

/// The DTD-subset strictness landed with the OASIS/NIST conformance pass:
/// unknown or malformed markup declarations, the exact `%name;` parameter-
/// reference grammar, strict declaration names, NDATA rules, notation tails,
/// conditional-section keywords and balance, external-subset error
/// propagation with text declarations, and PI target separation.
@Suite("DTD subset strictness")
struct DTDSubsetStrictnessTests {
    private func limits() -> PureXML.Parsing.Limits {
        PureXML.Parsing.Limits(allowDoctype: true)
    }

    private func parses(_ xml: String) -> Bool {
        (try? PureXML.parse(xml, limits: limits())) != nil
    }

    private func parses(_ xml: String, externalSubset: String) -> Bool {
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, _ in nil },
            resolveExternalSubset: { _ in externalSubset },
        )
        return (try? PureXML.parse(xml, limits: limits(), resolver: resolver)) != nil
    }

    private let externalHost = "<!DOCTYPE doc SYSTEM \"sub.dtd\">\n<doc/>"

    @Test("Unknown, lowercase, or space-separated declaration keywords are rejected")
    func test_declarationKeywords() {
        #expect(!parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY><!DUNNO junk>]>\n<doc/>"))
        #expect(!parses("<!DOCTYPE doc [<!element doc EMPTY>]>\n<doc/>"))
        #expect(!parses("<!DOCTYPE doc [<! ENTITY ge \"v\">]>\n<doc/>"))
        #expect(parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY>]>\n<doc/>"))
    }

    @Test("A parameter-entity reference is '%' Name ';' exactly")
    func test_parameterReferenceGrammar() {
        let declare = "<!ELEMENT doc EMPTY><!ENTITY % pe \"<!---->\">"
        #expect(!parses("<!DOCTYPE doc [\(declare)%pe<!---->]>\n<doc/>"))
        #expect(!parses("<!DOCTYPE doc [\(declare)% pe;]>\n<doc/>"))
        #expect(!parses("<!DOCTYPE doc [\(declare)%pe ;]>\n<doc/>"))
        #expect(parses("<!DOCTYPE doc [\(declare)%pe;]>\n<doc/>"))
    }

    @Test("Entity and parameter-entity names must start with a name-start character")
    func test_strictEntityNames() {
        #expect(!parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY><!ENTITY -ge \"v\">]>\n<doc/>"))
        #expect(!parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY><!ENTITY % .pe \"v\">]>\n<doc/>"))
        #expect(parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY><!ENTITY ge \"v\">]>\n<doc/>"))
    }

    @Test("NDATA requires whitespace and a strict notation name")
    func test_ndataNames() {
        let notation = "<!NOTATION n SYSTEM \"x\">"
        #expect(!parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY>\(notation)<!ENTITY ge SYSTEM \"e\" NDATA>]>\n<doc/>"))
        #expect(!parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY>\(notation)<!ENTITY ge SYSTEM \"e\" NDATA -n>]>\n<doc/>"))
        #expect(parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY>\(notation)<!ENTITY ge SYSTEM \"e\" NDATA n>]>\n<doc/>"))
    }

    @Test("A notation declaration requires its identifier and a clean tail")
    func test_notationTail() {
        #expect(!parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY><!NOTATION n SYSTEM \"\"\">]>\n<doc/>"))
        #expect(!parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY><!NOTATION n>]>\n<doc/>"))
        #expect(parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY><!NOTATION n PUBLIC \"p\">]>\n<doc/>"))
    }

    @Test("An entity value literal admits no bare '%' or '&'")
    func test_entityLiteralReferences() {
        #expect(!parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY><!ENTITY % e \"asdf%\">"))
        #expect(!parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY><!ENTITY % e \"asdf&\">"))
        #expect(parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY><!ENTITY % e \"a%pe;b\">"))
    }

    @Test("Conditional-section keywords are case-sensitive INCLUDE or IGNORE and must balance")
    func test_conditionalSections() {
        #expect(!parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY><![TEMP[<!ATTLIST doc a CDATA #IMPLIED>]]>"))
        #expect(!parses(externalHost, externalSubset: "<![include[<!ELEMENT doc EMPTY>]]>"))
        #expect(!parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY><![ignore[]]>"))
        #expect(!parses(externalHost, externalSubset: "<![INCLUDE[<!ELEMENT doc EMPTY>] ]>"))
        #expect(!parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY><![IGNORE[<![]]>"))
        #expect(!parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY><![IGNORE[ x ]]>]]>"))
        #expect(parses(externalHost, externalSubset: "<![INCLUDE[<!ELEMENT doc EMPTY>]]>"))
        #expect(parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY><![IGNORE[ <![ x ]]> ]]>"))
    }

    @Test("External-subset grammar violations reject the document")
    func test_externalSubsetPropagates() {
        #expect(!parses(externalHost, externalSubset: "<!DOCTYPE doc [<!ELEMENT doc EMPTY>]>"))
        #expect(parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY>"))
    }

    @Test("A text declaration allows version and requires encoding, never standalone")
    func test_textDeclaration() {
        #expect(parses(externalHost, externalSubset: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!ELEMENT doc EMPTY>"))
        #expect(parses(externalHost, externalSubset: "<?xml encoding=\"UTF-8\"?>\n<!ELEMENT doc EMPTY>"))
        #expect(!parses(externalHost, externalSubset: "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<!ELEMENT doc EMPTY>"))
        #expect(!parses(externalHost, externalSubset: "<?xml version=\"1.0\"?>\n<!ELEMENT doc EMPTY>"))
    }

    @Test("A processing-instruction target must be separated from its data")
    func test_processingInstructionSeparation() {
        #expect(!parses("<?pitarget+++?>\n<doc/>"))
        #expect(parses("<?pitarget +++?>\n<doc/>"))
        #expect(parses("<?pitarget?>\n<doc/>"))
    }

    @Test("The internal subset admits only declarations, PE references, and whitespace")
    func test_subsetJunk() {
        #expect(!parses("<!DOCTYPE doc [<!ELEMENT doc EMPTY> junk ]>\n<doc/>"))
        #expect(!parses(externalHost, externalSubset: "<!ELEMENT doc EMPTY> ]]>"))
    }
}
