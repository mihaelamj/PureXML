@testable import PureXML
import Testing

@Suite("External and parameter entities")
struct EntityResolverTests {
    private let dtdAllowed = PureXML.Parsing.Limits(allowDoctype: true)

    // MARK: Parameter entities

    @Test("A parameter entity is expanded inside a general entity value")
    func test_parameterEntityInValue() throws {
        let xml = """
        <!DOCTYPE r [
        <!ENTITY % greeting "hello">
        <!ENTITY msg "%greeting; world">
        ]><r>&msg;</r>
        """
        let node = try PureXML.parse(xml, limits: dtdAllowed)
        #expect(text(of: node) == "hello world")
    }

    @Test("A later parameter entity composes an earlier one")
    func test_parameterEntityComposition() throws {
        let xml = """
        <!DOCTYPE r [
        <!ENTITY % a "x">
        <!ENTITY % b "%a;y">
        <!ENTITY e "%b;z">
        ]><r>&e;</r>
        """
        let node = try PureXML.parse(xml, limits: dtdAllowed)
        #expect(text(of: node) == "xyz")
    }

    @Test("A bare parameter-entity reference injects markup declarations")
    func test_parameterEntityInjectsDeclarations() throws {
        let xml = """
        <!DOCTYPE r [
        <!ENTITY % decls "<!ENTITY inner 'deep'>">
        %decls;
        ]><r>&inner;</r>
        """
        let node = try PureXML.parse(xml, limits: dtdAllowed)
        #expect(text(of: node) == "deep")
    }

    @Test("Parameter entities are recorded on the document type")
    func test_parameterEntitiesRecorded() throws {
        let xml = "<!DOCTYPE r [<!ENTITY % p \"v\">]><r/>"
        let parsed = try PureXML.Parsing.Parser().parseWithDocumentType(xml, limits: dtdAllowed)
        #expect(parsed.documentType.parameterEntities["p"] == "v")
    }

    // MARK: External entities

    @Test("An external entity is refused by default, keeping XXE closed")
    func test_externalEntityRefusedByDefault() {
        let xml = "<!DOCTYPE r [<!ENTITY ext SYSTEM \"file:///etc/passwd\">]><r>&ext;</r>"
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: dtdAllowed)
        }
    }

    @Test("An external entity is recorded with its system identifier")
    func test_externalEntityRecorded() throws {
        let xml = "<!DOCTYPE r [<!ENTITY ext SYSTEM \"urn:x\">]><r/>"
        let parsed = try PureXML.Parsing.Parser().parseWithDocumentType(xml, limits: dtdAllowed)
        #expect(parsed.documentType.externalEntities["ext"] == .init(systemID: "urn:x"))
    }

    @Test("An injected resolver supplies external entity replacement text")
    func test_resolverSuppliesEntity() throws {
        let xml = "<!DOCTYPE r [<!ENTITY ext SYSTEM \"urn:greeting\">]><r>&ext;</r>"
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, id in id.systemID == "urn:greeting" ? "resolved" : nil },
        )
        let node = try PureXML.parse(xml, limits: dtdAllowed, resolver: resolver)
        #expect(text(of: node) == "resolved")
    }

    @Test("A resolver that refuses a specific entity leaves it undefined")
    func test_resolverRefusesSpecific() {
        let xml = "<!DOCTYPE r [<!ENTITY ext SYSTEM \"urn:x\">]><r>&ext;</r>"
        let resolver = PureXML.Parsing.EntityResolver(resolveEntity: { _, _ in nil })
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: dtdAllowed, resolver: resolver)
        }
    }

    @Test("A PUBLIC external entity carries both identifiers to the resolver")
    func test_publicIdentifier() throws {
        let xml = "<!DOCTYPE r [<!ENTITY ext PUBLIC \"-//x//EN\" \"urn:x\">]><r>&ext;</r>"
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, id in "\(id.publicID ?? "nil")|\(id.systemID)" },
        )
        let node = try PureXML.parse(xml, limits: dtdAllowed, resolver: resolver)
        #expect(text(of: node) == "-//x//EN|urn:x")
    }

    // MARK: External subset

    @Test("The external subset identifier is recorded from the DOCTYPE")
    func test_externalSubsetRecorded() throws {
        let xml = "<!DOCTYPE r SYSTEM \"urn:dtd\"><r/>"
        let parsed = try PureXML.Parsing.Parser().parseWithDocumentType(xml, limits: dtdAllowed)
        #expect(parsed.documentType.externalSubset == .init(systemID: "urn:dtd"))
    }

    @Test("The external subset is loaded through the resolver and its entities used")
    func test_externalSubsetLoaded() throws {
        let xml = "<!DOCTYPE r SYSTEM \"urn:dtd\"><r>&fromdtd;</r>"
        let resolver = PureXML.Parsing.EntityResolver(
            resolveExternalSubset: { $0.systemID == "urn:dtd" ? "<!ENTITY fromdtd \"external\">" : nil },
        )
        let node = try PureXML.parse(xml, limits: dtdAllowed, resolver: resolver)
        #expect(text(of: node) == "external")
    }

    @Test("Internal declarations win over the external subset")
    func test_internalWinsOverExternal() throws {
        let xml = "<!DOCTYPE r SYSTEM \"urn:dtd\" [<!ENTITY e \"inner\">]><r>&e;</r>"
        let resolver = PureXML.Parsing.EntityResolver(
            resolveExternalSubset: { _ in "<!ENTITY e \"outer\">" },
        )
        let node = try PureXML.parse(xml, limits: dtdAllowed, resolver: resolver)
        #expect(text(of: node) == "inner")
    }

    @Test("The external subset is not fetched without a resolver")
    func test_externalSubsetNotFetchedByDefault() {
        let xml = "<!DOCTYPE r SYSTEM \"urn:dtd\"><r>&fromdtd;</r>"
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: dtdAllowed)
        }
    }

    // MARK: Helpers

    private func text(of node: PureXML.Model.Node) -> String {
        var result = ""
        collect(node, into: &result)
        return result
    }

    private func collect(_ node: PureXML.Model.Node, into result: inout String) {
        switch node {
        case let .document(children):
            for child in children {
                collect(child, into: &result)
            }
        case let .element(element):
            for child in element.children {
                collect(child, into: &result)
            }
        case let .text(value), let .cdata(value):
            result += value
        default:
            break
        }
    }
}
