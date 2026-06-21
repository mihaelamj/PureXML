import Testing
@testable import PureXML

/// Attribute-pass schema compile findings (an attribute declared in the XSI
/// namespace, a duplicate attribute use within a complex type, an attribute
/// reference contradicting a global `fixed` value, and a restriction that relaxes
/// a base attribute) carry validation coding paths that resolve to source spans,
/// the IDE underline flow for #169. Split from the other located-diagnostics
/// suites to keep each suite within the type-body length budget.
@Suite("Schema attribute-pass located compile diagnostics")
struct SchemaAttributeLocatedDiagnosticsTests {
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

    @Test("An attribute declared in the XSI namespace is located on the attribute")
    func test_xsiNamespaceAttributeLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://www.w3.org/2001/XMLSchema-instance">
          <xs:attribute name="foo" type="xs:string"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("is in the XSI namespace, which is not allowed") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:attribute"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }

    @Test("A duplicate attribute use is located on its declaring complex type")
    func test_duplicateAttributeUseLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="t">
            <xs:attribute name="a" type="xs:string"/>
            <xs:attribute name="a" type="xs:string"/>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("has more than one attribute named 'a'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("An attribute reference contradicting a fixed value is located on the reference")
    func test_attributeRefFixedValueLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:attribute name="a" type="xs:string" fixed="x"/>
          <xs:complexType name="t">
            <xs:attribute ref="a" fixed="y"/>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("must use its fixed value 'x', not 'y'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:attribute"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 4)
    }

    @Test("A restriction relaxing a required base attribute is located on the restriction")
    func test_attributeRestrictionLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base">
            <xs:attribute name="a" type="xs:string" use="required"/>
          </xs:complexType>
          <xs:complexType name="d">
            <xs:complexContent>
              <xs:restriction base="base">
                <xs:attribute name="a" type="xs:string" use="optional"/>
              </xs:restriction>
            </xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("is required in the base type and a restriction may not make it optional") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:complexContent", "xs:restriction"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 7)
    }
}
