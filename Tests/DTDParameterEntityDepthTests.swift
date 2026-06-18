import Testing
@testable import PureXML

@Suite("DTD parameter-entity and external-subset depth")
struct DTDParameterEntityDepthTests {
    private let dtdAllowed = PureXML.Parsing.Limits(allowDoctype: true)

    private func documentType(_ xml: String, resolver: PureXML.Parsing.EntityResolver = .refusing) throws -> PureXML.Parsing.DocumentType {
        try PureXML.Parsing.Parser().parseWithDocumentType(xml, limits: dtdAllowed, resolver: resolver).documentType
    }

    private func rootText(_ node: PureXML.Model.Node) -> String {
        guard case let .document(children) = node else { return "" }
        for case let .element(element) in children {
            return element.text
        }
        return ""
    }

    @Test("A parameter entity expands within an element-model declaration")
    func test_parameterEntityInElementModel() throws {
        let dtd = try documentType("<!DOCTYPE r [<!ENTITY % m \"(a|b)\"><!ELEMENT r %m;>]><r/>")
        #expect(dtd.elementModels["r"] == "(a|b)")
    }

    @Test("A parameter entity expands within an attribute-list declaration")
    func test_parameterEntityInAttlist() throws {
        let xml = "<!DOCTYPE r [<!ELEMENT r EMPTY><!ENTITY % atts \"code CDATA #REQUIRED\"><!ATTLIST r %atts;>]><r/>"
        // The attribute is declared via the PE, so a missing required code is caught.
        let errors = try PureXML.validateAgainstInternalDTD(xml)
        #expect(errors.contains { $0.reason.contains("code") })
    }

    @Test("Deeply nested parameter entities compose fully")
    func test_deepNesting() throws {
        let xml = """
        <!DOCTYPE r [
        <!ENTITY % a "1">
        <!ENTITY % b "%a;2">
        <!ENTITY % c "%b;3">
        <!ENTITY % d "%c;4">
        <!ENTITY e "%d;5">
        ]><r>&e;</r>
        """
        try #expect(rootText(PureXML.parse(xml, limits: dtdAllowed)) == "12345")
    }

    @Test("An external subset can itself load a further external parameter entity")
    func test_recursiveExternalLoading() throws {
        let resolver = PureXML.Parsing.EntityResolver(resolveExternalSubset: { id in
            switch id.systemID {
            case "a.dtd": "<!ENTITY % inner SYSTEM \"b.dtd\">%inner;<!ELEMENT r (#PCDATA)>"
            case "b.dtd": "<!ENTITY deep \"found\">"
            default: nil
            }
        })
        let xml = "<!DOCTYPE r [<!ENTITY % ext SYSTEM \"a.dtd\">%ext;]><r>&deep;</r>"
        let node = try PureXML.parse(xml, limits: dtdAllowed, resolver: resolver)
        #expect(rootText(node) == "found")
    }
}
