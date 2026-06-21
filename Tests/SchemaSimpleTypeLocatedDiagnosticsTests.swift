import Testing
@testable import PureXML

/// Simple-type-pass schema compile findings (variety constraints, a complex base
/// under a simpleType restriction, `final` enforcement for list/union derivation,
/// and an attribute typed by a complex type) carry validation coding paths that
/// resolve to source spans, the IDE underline flow for #169. Split from the other
/// located-diagnostics suites to keep each suite within the type-body length budget.
@Suite("Schema simple-type-pass located compile diagnostics")
struct SchemaSimpleTypeLocatedDiagnosticsTests {
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

    @Test("An empty union is located on the union element")
    func test_emptyUnionLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="t"><xs:union/></xs:simpleType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("a union must declare at least one member type") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:simpleType", "xs:union"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("A simpleType restriction of a complex base is located on the restriction")
    func test_simpleTypeBaseComplexLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ct"><xs:sequence/></xs:complexType>
          <xs:simpleType name="t"><xs:restriction base="ct"/></xs:simpleType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("of simpleType restriction must be a simple type") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:simpleType", "xs:restriction"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }

    @Test("A list item type that is final for list is located on the list element")
    func test_listItemFinalLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="it" final="list"><xs:restriction base="xs:string"/></xs:simpleType>
          <xs:simpleType name="t"><xs:list itemType="it"/></xs:simpleType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("is final for 'list' and may not be a list item type") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:simpleType", "xs:list"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }

    @Test("An attribute typed by a complex type is located on the attribute")
    func test_attributeTypeComplexLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ct"><xs:sequence/></xs:complexType>
          <xs:complexType name="t">
            <xs:attribute name="a" type="ct"/>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("an attribute's type must be a simple type, not the complex type") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:attribute"])

        let (tree, _) = PureXML.readTree(xsd)
        let range = tree.sourceRange(at: located.codingPath)
        #expect(range?.start.line == 4)
        #expect(range?.start.column == 5)
    }
}
