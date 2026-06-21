import Testing
@testable import PureXML

/// Content-derivation-pass schema compile findings (the `complexExtensionBaseValid`
/// bundle: simpleContent/complexContent base-kind rules, a simpleContent
/// restriction's inline-type faithfulness, the mixed-agreement rule, and an
/// element value constraint over element-only content) carry validation coding
/// paths that resolve to source spans, the IDE underline flow for #169. Each
/// derivation error underlines its `extension`/`restriction` node (or the element
/// declaration). Split from the other located-diagnostics suites to keep each
/// suite within the type-body length budget.
@Suite("Schema content-derivation-pass located compile diagnostics")
struct SchemaContentDerivationLocatedTests {
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

    @Test("A complexContent extension adding element content over a simpleContent base is located on the extension")
    func test_simpleContentExtensionBaseLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base">
            <xs:simpleContent><xs:extension base="xs:string"/></xs:simpleContent>
          </xs:complexType>
          <xs:complexType name="d">
            <xs:complexContent>
              <xs:extension base="base">
                <xs:sequence><xs:element name="e" type="xs:string"/></xs:sequence>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("may not extend 'base', which has simple content") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:complexContent", "xs:extension"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 7)
    }

    @Test("A simpleContent restriction with a built-in base is located on the restriction")
    func test_simpleContentRestrictionBaseLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="t">
            <xs:simpleContent>
              <xs:restriction base="xs:string"/>
            </xs:simpleContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("a simpleContent restriction's base must be a complex type, not the built-in simple type 'string'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:simpleContent", "xs:restriction"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 4)
    }

    @Test("An unfaithful inline type in a simpleContent restriction is located on the restriction")
    func test_simpleContentRestrictionTypeLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base">
            <xs:simpleContent><xs:extension base="xs:decimal"/></xs:simpleContent>
          </xs:complexType>
          <xs:complexType name="d">
            <xs:simpleContent>
              <xs:restriction base="base">
                <xs:simpleType><xs:list itemType="xs:int"/></xs:simpleType>
              </xs:restriction>
            </xs:simpleContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("the inline simpleType in a simpleContent restriction is not a valid restriction of base type 'base'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:simpleContent", "xs:restriction"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 7)
    }

    @Test("A complexContent base that is a built-in simple type is located on the derivation")
    func test_complexContentBaseKindLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="t">
            <xs:complexContent>
              <xs:extension base="xs:string"/>
            </xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("a complexContent base must be a complex type, not the built-in simple type 'string'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:complexContent", "xs:extension"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 4)
    }

    @Test("A simpleContent extension whose base is xs:anyType is located on the extension")
    func test_simpleContentExtensionBaseKindLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="t">
            <xs:simpleContent>
              <xs:extension base="xs:anyType"/>
            </xs:simpleContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings
            .first { $0.reason.contains("a simpleContent extension's base must be a simple type or a complex type with simple content, not 'anyType'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:simpleContent", "xs:extension"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 4)
    }

    @Test("An element value constraint over element-only content is located on the element")
    func test_elementValueConstraintContentLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="e" fixed="x">
            <xs:complexType><xs:sequence><xs:element name="c" type="xs:string"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("an element with a 'default' or 'fixed' value must have simple or mixed content") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("A complexContent extension with a mismatched mixed setting is located on the extension")
    func test_extensionMixedAgreementLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base" mixed="true">
            <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="d">
            <xs:complexContent>
              <xs:extension base="base">
                <xs:sequence><xs:element name="b" type="xs:string"/></xs:sequence>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("must have the same mixed setting as its base") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:complexContent", "xs:extension"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 7)
    }
}
