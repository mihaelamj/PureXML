import Testing
@testable import PureXML

/// Structure-pass schema compile findings (facet applicability, top-level and
/// nested declaration rules, empty namespaces, all-group references) carry
/// validation coding paths that resolve to source spans, the IDE underline flow
/// for #169. Split from `SchemaLocatedDiagnosticsTests` to keep each suite within
/// the type-body length budget.
@Suite("Schema structure-pass located compile diagnostics")
struct SchemaStructureLocatedDiagnosticsTests {
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

    @Test("A facet that does not apply to a list variety is located on its declaring simpleType")
    func test_varietyFacetLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="ints"><xs:list itemType="xs:integer"/></xs:simpleType>
          <xs:simpleType name="t">
            <xs:restriction base="ints"><xs:maxInclusive value="5"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("'maxInclusive' does not apply to a list type") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:simpleType"])

        let (tree, _) = PureXML.readTree(xsd)
        let range = tree.sourceRange(at: located.codingPath)
        #expect(range?.start.line == 3)
    }

    @Test("A top-level declaration without a name is located on the declaration")
    func test_topLevelMissingNameLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element type="xs:string"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("top-level 'element' definition must have a 'name'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        let range = tree.sourceRange(at: located.codingPath)
        #expect(range?.start.line == 2)
        #expect(range?.start.column == 3)
    }

    @Test("A nested named definition is located on the offending nested component")
    func test_nestedNamedDefinitionLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="a">
            <xs:simpleType name="bad"><xs:restriction base="xs:string"/></xs:simpleType>
          </xs:element>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("nested 'simpleType' definition may not have a 'name'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element", "xs:simpleType"])

        let (tree, _) = PureXML.readTree(xsd)
        let range = tree.sourceRange(at: located.codingPath)
        #expect(range?.start.line == 3)
    }

    @Test("A restriction of xs:anySimpleType is located on the restriction")
    func test_anySimpleTypeRestrictionLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t">
          <xs:simpleType name="t"><xs:restriction base="xs:anySimpleType"/></xs:simpleType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("restriction of 'xs:anySimpleType' is not allowed") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:simpleType", "xs:restriction"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("A facet on anySimpleType-based simpleContent is located on the restriction")
    func test_anySimpleTypeFacetLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base">
            <xs:simpleContent><xs:extension base="xs:anySimpleType"/></xs:simpleContent>
          </xs:complexType>
          <xs:complexType name="t">
            <xs:simpleContent>
              <xs:restriction base="base"><xs:minLength value="1"/></xs:restriction>
            </xs:simpleContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("constraining facet may not be applied to anySimpleType") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:simpleContent", "xs:restriction"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 7)
    }

    @Test("An empty targetNamespace is located on the schema element")
    func test_emptyTargetNamespaceLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="">
          <xs:element name="a" type="xs:string"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("'targetNamespace' attribute may not be the empty string") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 1)
    }

    @Test("An all-group reference with an illegal maxOccurs is located on the reference")
    func test_allGroupReferenceMaxOccursLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:group name="g"><xs:all><xs:element name="a" type="xs:string"/></xs:all></xs:group>
          <xs:complexType name="t"><xs:group ref="g" maxOccurs="2"/></xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("maxOccurs of a reference to an all group must be 1") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:group"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }
}
