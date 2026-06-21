import Testing
@testable import PureXML

/// Composition/redefine-pass schema compile findings (a resolved schemaLocation
/// whose content is not a schema, a redefined type that does not restrict or extend
/// itself, and a redefined group self-reference with an illegal occurrence) carry
/// validation coding paths that resolve to source spans, the IDE underline flow for
/// #169. These rules require a loaded external document, so the tests supply a
/// `schemaLoader`; the redefine attribute-group and model-group restriction checkers
/// share the same node-location idiom (the redefinition declaration) and are
/// exercised by the XSTS suite. Split from the other located-diagnostics suites to
/// keep each suite within the type-body length budget.
@Suite("Schema composition/redefine-pass located compile diagnostics")
struct SchemaCompositionLocatedDiagnosticsTests {
    private func inconsistentFindings(
        in xsd: String,
        loader: @escaping (String) -> String?,
    ) throws -> [PureXML.Validation.ValidationError] {
        do {
            _ = try PureXML.Schema.Document(xsd, schemaLoader: loader)
            Issue.record("expected schema compilation to fail")
            return []
        } catch let error as PureXML.Schema.SchemaError {
            guard case let .inconsistent(findings) = error else {
                Issue.record("expected .inconsistent, got \(error)")
                return []
            }
            return findings
        }
    }

    @Test("A schemaLocation resolving to non-schema content is located on the reference")
    func test_referencedSchemaNotValidLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:include schemaLocation="broken.xsd"/>
          <xs:element name="root" type="xs:string"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd) { _ in "<notSchema/>" }
        let located = try #require(findings.first { $0.reason.contains("the referenced schema document 'broken.xsd' is not a valid schema") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:include"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("A redefined type that does not restrict or extend itself is located on the type")
    func test_redefineDerivationLocated() throws {
        let base = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t">
          <xs:complexType name="ct"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:complexType>
          <xs:complexType name="other"><xs:sequence/></xs:complexType>
        </xs:schema>
        """
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:t="urn:t" targetNamespace="urn:t">
          <xs:redefine schemaLocation="base.xsd">
            <xs:complexType name="ct">
              <xs:complexContent>
                <xs:extension base="t:other"/>
              </xs:complexContent>
            </xs:complexType>
          </xs:redefine>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd) { _ in base }
        let located = try #require(findings.first { $0.reason.contains("redefined type 'ct' must restrict or extend itself") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:redefine", "xs:complexType"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }

    @Test("A redefined group self-reference with an illegal occurrence is located on the reference")
    func test_redefineSelfReferenceLocated() throws {
        let base = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t">
          <xs:group name="g"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:group>
        </xs:schema>
        """
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:t="urn:t" targetNamespace="urn:t">
          <xs:redefine schemaLocation="base.xsd">
            <xs:group name="g">
              <xs:sequence>
                <xs:group ref="t:g" maxOccurs="2"/>
              </xs:sequence>
            </xs:group>
          </xs:redefine>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd) { _ in base }
        let located = try #require(findings.first { $0.reason.contains("a redefined group's self-reference must have minOccurs and maxOccurs of 1") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:redefine", "xs:group", "xs:sequence", "xs:group"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 5)
    }
}
