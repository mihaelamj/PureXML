@testable import PureXML
import Testing

/// OASIS XML Catalog conformance, driven through the validation framework
/// (Tier 2): entry kinds and the precedence the spec prescribes.
@Suite("Conformance corpus: XML Catalog")
struct ConformanceCatalogTests {
    private let catalog = """
    <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
      <public publicId="-//ACME//DTD One//EN" uri="local/one.dtd"/>
      <system systemId="http://example.com/exact.dtd" uri="local/exact.dtd"/>
      <rewriteSystem systemIdStartString="http://example.com/dtd/" rewritePrefix="local/dtd/"/>
      <uri name="urn:asset" uri="local/asset.bin"/>
      <rewriteURI uriStartString="http://example.com/res/" rewritePrefix="local/res/"/>
    </catalog>
    """

    private func corpus() throws -> [PureXML.Validation.ConformanceCase] {
        let resolver = try PureXML.Catalog.Resolver(catalog)
        func resolved(_ value: String?) -> String {
            value ?? "(unresolved)"
        }
        return [
            .init(name: "system-exact", actual: resolved(resolver.resolveSystem("http://example.com/exact.dtd")), expected: "local/exact.dtd"),
            .init(name: "rewrite-system-prefix", actual: resolved(resolver.resolveSystem("http://example.com/dtd/a.dtd")), expected: "local/dtd/a.dtd"),
            .init(name: "public-id", actual: resolved(resolver.resolvePublic("-//ACME//DTD One//EN")), expected: "local/one.dtd"),
            .init(name: "uri-exact", actual: resolved(resolver.resolveURI("urn:asset")), expected: "local/asset.bin"),
            .init(name: "rewrite-uri-prefix", actual: resolved(resolver.resolveURI("http://example.com/res/x.png")), expected: "local/res/x.png"),
            .init(name: "unmatched-system", actual: resolved(resolver.resolveSystem("http://other.example/none.dtd")), expected: "(unresolved)"),
            .init(name: "unmatched-uri", actual: resolved(resolver.resolveURI("urn:none")), expected: "(unresolved)"),
        ]
    }

    @Test("The XML Catalog conformance corpus passes with no located failures")
    func test_catalogCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: corpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
