@testable import PureXML

enum ValidationRuleTestSupport {
    typealias DTDSchema = PureXML.Validation.DTDSchema
    typealias XSDContext = PureXML.Validation.XSDContext

    static func dtd(_ xml: String, resolver: PureXML.Parsing.EntityResolver = .refusing) throws -> (PureXML.Model.Node, DTDSchema) {
        let parsed = try PureXML.Parsing.Parser().parseWithDocumentType(xml, limits: .init(allowDoctype: true), resolver: resolver)
        let standalone = parsed.declaration?.standalone == true
        return (parsed.node, DTDSchema(parsed.documentType, standalone: standalone))
    }

    static let standaloneExternalDTD = """
    <!ELEMENT root (child)*>
    <!ELEMENT child (#PCDATA)>
    <!ATTLIST root token (a|b|c) "a" id ID #IMPLIED>
    """

    static func standaloneResolver() -> PureXML.Parsing.EntityResolver {
        let dtd = standaloneExternalDTD
        return PureXML.Parsing.EntityResolver(
            resolveEntity: { _, _ in nil },
            resolveExternalSubset: { _ in dtd },
        )
    }

    static func path(_ error: PureXML.Validation.ValidationError) -> [String] {
        error.codingPath.map(\.stringValue)
    }
}
