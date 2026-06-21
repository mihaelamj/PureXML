import Testing
@testable import PureXML

/// Extension/substitution-pass schema compile findings (an `all` group reached
/// through extension, an anonymous complex-type restriction that is not a subset of
/// its base, and a substitution-group member whose type is not derived from its
/// head) carry validation coding paths that resolve to source spans, the IDE
/// underline flow for #169. Split from the other located-diagnostics suites to keep
/// each suite within the type-body length budget.
@Suite("Schema extension/substitution-pass located compile diagnostics")
struct SchemaExtensionSubstitutionLocatedTests {
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

    @Test("An all-group extending a base with content is located on the extension")
    func test_extensionAllGroupLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base">
            <xs:sequence><xs:element name="x" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="d">
            <xs:complexContent>
              <xs:extension base="base">
                <xs:all><xs:element name="y" type="xs:string"/></xs:all>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("an 'all' group may not extend the type 'base'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:complexContent", "xs:extension"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 7)
    }

    @Test("An invalid anonymous restriction is located on the restriction")
    func test_anonymousRestrictionLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base">
            <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:element name="root">
            <xs:complexType>
              <xs:complexContent>
                <xs:restriction base="base">
                  <xs:sequence><xs:element name="b" type="xs:string"/></xs:sequence>
                </xs:restriction>
              </xs:complexContent>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("an anonymous complex type is not a valid restriction of 'base'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element", "xs:complexType", "xs:complexContent", "xs:restriction"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 8)
    }

    @Test("A substitution member with an underived type is located on the member element")
    func test_substitutionTypeLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:element name="head" type="xs:string"/>
          <xs:element name="member" type="xs:int" substitutionGroup="t:head"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("element 'member' may not be in the substitution group of 'head'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }
}
