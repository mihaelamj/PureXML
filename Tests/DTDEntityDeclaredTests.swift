@testable import PureXML
import Testing

/// The IBM-section burn-down behaviors: a document needs a root element
/// (production 1), entity references in literals must be lexical Names (P66),
/// WFC: No Recursion is checked at declaration (P69), an undeclared
/// parameter-entity reference is a WFC or a VC depending on standalone and
/// external declarations (production 68), and a content-model group split
/// across parameter entities is a validity finding (VC: Proper Group/PE
/// Nesting, P49).
@Suite("Entity declared and recursion constraints")
struct DTDEntityDeclaredTests {
    private func limits() -> PureXML.Parsing.Limits {
        PureXML.Parsing.Limits(allowDoctype: true)
    }

    @Test("A document without a root element is rejected")
    func test_missingRoot() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse("<?xml version=\"1.0\"?>\n<!DOCTYPE book [<!ELEMENT book ANY>]>\n<!-- element is missing -->", limits: limits())
        }
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse("<!-- only a comment -->")
        }
    }

    @Test("An entity reference in a literal must be a Name or character reference")
    func test_referenceNameInLiteral() {
        let xml = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ENTITY aaa \"wrong: &49;\">]>\n<r/>"
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: limits())
        }
        let legal = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ENTITY aaa \"fine: &#49;\">]>\n<r/>"
        #expect((try? PureXML.parse(legal, limits: limits())) != nil)
    }

    @Test("Recursive entity declarations are rejected without being referenced")
    func test_declarationRecursion() {
        let direct = """
        <!DOCTYPE root [
        <!ELEMENT root (#PCDATA)>
        <!ENTITY % paaa "&bbb;">
        <!ENTITY bbb "%paaa;">
        ]>
        <root/>
        """
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(direct, limits: limits())
        }
        let indirect = """
        <!DOCTYPE root [
        <!ELEMENT root (#PCDATA)>
        <!ENTITY % paaa "&bbb;">
        <!ENTITY bbb "&ccc;">
        <!ENTITY ccc "%paaa;">
        ]>
        <root/>
        """
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(indirect, limits: limits())
        }
    }

    @Test("An undeclared PE reference is a WFC when standalone, a VC otherwise")
    func test_undeclaredParameterEntity() throws {
        let standalone = """
        <?xml version="1.0" standalone="yes"?>
        <!DOCTYPE root [
        <!ELEMENT root (#PCDATA)>
        %paaa;
        <!ENTITY % paaa "<!ATTLIST root att CDATA #IMPLIED>">
        ]>
        <root/>
        """
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(standalone, limits: limits())
        }
        // With an external PE in play the same reference is a validity finding.
        let loose = """
        <!DOCTYPE root [
        <!ELEMENT root (#PCDATA)>
        <!ENTITY % outside SYSTEM "x.ent">
        %outside;
        %undeclared;
        ]>
        <root/>
        """
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, _ in nil },
            resolveExternalSubset: { _ in "<!ATTLIST root att CDATA #IMPLIED>" },
        )
        let errors = try PureXML.validateAgainstInternalDTD(loose, resolver: resolver)
        #expect(errors.contains { $0.reason.contains("'%undeclared;' is referenced but not declared") })
    }

    @Test("A group split across parameter entities is a validity finding")
    func test_properGroupNesting() throws {
        let dtd = """
        <!ENTITY % choice1 "(a|b">
        <!ENTITY % choice2 "|c)">
        <!ELEMENT child1 %choice1;%choice2; >
        <!ELEMENT a EMPTY><!ELEMENT b EMPTY><!ELEMENT c EMPTY>
        """
        let xml = "<!DOCTYPE root SYSTEM \"x.dtd\" [<!ELEMENT root ANY>]>\n<root/>"
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, _ in nil },
            resolveExternalSubset: { _ in dtd },
        )
        let errors = try PureXML.validateAgainstInternalDTD(xml, resolver: resolver)
        #expect(errors.contains { $0.reason.contains("improper group/PE nesting") })
    }
}
