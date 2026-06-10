@testable import PureXML
import Testing

/// The strict internal-subset profile (#128): under
/// `Limits(strictInternalSubset: true)` the internal DTD subset is held to
/// the letter of XML 1.0, rejecting conditional sections and parameter-entity
/// references inside markup declarations, both of which PureXML otherwise
/// supports as features. Defaults are unchanged.
@Suite("Strict internal-subset profile")
struct StrictSubsetProfileTests {
    private let strict = PureXML.Parsing.Limits(allowDoctype: true, strictInternalSubset: true)
    private let lenient = PureXML.Parsing.Limits(allowDoctype: true)

    private func parses(_ xml: String, _ limits: PureXML.Parsing.Limits) -> Bool {
        (try? PureXML.parse(xml, limits: limits)) != nil
    }

    @Test("Conditional sections in the internal subset reject under the profile only")
    func test_conditionalSections() {
        let xml = "<!DOCTYPE doc [\n<![INCLUDE[ ]]>\n]>\n<doc></doc>"
        #expect(!parses(xml, strict))
        #expect(parses(xml, lenient))
    }

    @Test("PE references inside declarations reject under the profile only")
    func test_referencesInDeclarations() {
        let inEntityValue = "<!DOCTYPE doc [<!ELEMENT doc (#PCDATA)><!ENTITY % e \"\"><!ENTITY foo \"%e;\">]>\n<doc></doc>"
        let inContentModel = "<!DOCTYPE doc [<!ENTITY % e \"#PCDATA\"><!ELEMENT doc (%e;)>]>\n<doc></doc>"
        let inPEValue = "<!DOCTYPE doc [<!ELEMENT doc (#PCDATA)><!ENTITY % e1 \"\"><!ENTITY % e2 \"%e1;\">]>\n<doc></doc>"
        let inAttList = "<!DOCTYPE doc [<!ELEMENT doc ANY><!ENTITY % p \"a\"><!ATTLIST doc %p; CDATA #IMPLIED>]>\n<doc/>"
        for xml in [inEntityValue, inContentModel, inPEValue, inAttList] {
            #expect(!parses(xml, strict))
            #expect(parses(xml, lenient))
        }
    }

    @Test("DeclSep references and quoted defaults stay legal under the profile")
    func test_legalShapesUnaffected() {
        // A bare %pe; between declarations is production 28a DeclSep.
        let declSep = "<!DOCTYPE doc [<!ENTITY % pe \"<!ELEMENT doc ANY>\">%pe;]>\n<doc/>"
        #expect(parses(declSep, strict))
        // '%e;' inside a quoted default is an AttValue: literal text.
        let quotedDefault = "<!DOCTYPE doc [<!ENTITY % e \"foo\"><!ELEMENT doc (#PCDATA)><!ATTLIST doc a1 CDATA \"%e;\">]>\n<doc></doc>"
        #expect(parses(quotedDefault, strict))
    }
}
