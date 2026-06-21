import Testing
@testable import PureXML

/// Derivation/cycle-pass schema compile findings (a type derived from itself, an
/// element in its own substitution group, a model group referencing itself, and
/// an all-group referenced inside a compositor) carry validation coding paths that
/// resolve to source spans, the IDE underline flow for #169. The cycle checkers
/// report by component name over a name-keyed graph, so each finding now locates
/// on the declaring node recorded alongside that graph. Split from the other
/// located-diagnostics suites to keep each suite within the type-body length budget.
@Suite("Schema derivation/cycle-pass located compile diagnostics")
struct SchemaDerivationLocatedDiagnosticsTests {
    private func inconsistentFindings(in xsd: String) throws -> [PureXML.Validation.ValidationError] {
        do {
            _ = try PureXML.Schema.Document(xsd)
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

    @Test("A type derived from itself is located on the type declaration")
    func test_derivationCycleLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:complexType name="a">
            <xs:complexContent>
              <xs:extension base="t:a"/>
            </xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("type 'a' must not be derived from itself") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("An element in its own substitution group is located on the element")
    func test_substitutionCycleLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:element name="a" type="xs:string" substitutionGroup="t:a"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("element 'a' must not be a member of its own substitution group") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("A model group referencing itself is located on the group declaration")
    func test_groupReferenceCycleLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:group name="g">
            <xs:sequence><xs:group ref="t:g"/></xs:sequence>
          </xs:group>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("model group 'g' must not reference itself") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:group"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("An all-group referenced inside a compositor is located on the reference")
    func test_allGroupReferencePlacementLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:group name="g"><xs:all><xs:element name="a" type="xs:string"/></xs:all></xs:group>
          <xs:complexType name="t">
            <xs:sequence><xs:group ref="g"/></xs:sequence>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("may not be referenced inside a 'sequence'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:sequence", "xs:group"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 4)
    }
}
