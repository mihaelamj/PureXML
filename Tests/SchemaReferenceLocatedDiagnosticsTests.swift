import Testing
@testable import PureXML

/// Reference-resolution-pass schema compile findings now carry validation coding
/// paths that resolve to source spans, the IDE underline flow for #169.
/// `referenceFindings` previously wrapped its whole aggregate in `.unlocated`, so
/// every undeclared-reference error collapsed onto the schema root; each of its six
/// sub-collectors now attaches to the referencing node. The redefine-existence and
/// import-namespace families (which need a loaded external document) are exercised
/// by the XSTS suite rather than here. Split from the other located-diagnostics
/// suites to keep each suite within the type-body length budget.
@Suite("Schema reference-pass located compile diagnostics")
struct SchemaReferenceLocatedDiagnosticsTests {
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

    @Test("An undeclared element reference is located on the referencing element")
    func test_undeclaredElementRefLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root">
            <xs:complexType><xs:sequence><xs:element ref="missing"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("element ref references undeclared 'missing'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element", "xs:complexType", "xs:sequence", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }

    @Test("An undeclared type reference is located on the referencing element")
    func test_undeclaredTypeRefLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root" type="missing"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("type references undeclared type 'missing'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("A simpleContent restriction over a non-simpleContent base is located on the restriction")
    func test_simpleContentBaseLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base"><xs:sequence/></xs:complexType>
          <xs:complexType name="t">
            <xs:simpleContent><xs:restriction base="base"/></xs:simpleContent>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("of simpleContent restriction must be a simple type or complex type with simpleContent") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:simpleContent", "xs:restriction"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 4)
    }

    @Test("A reference to an un-imported namespace is located on the referencing element")
    func test_undeclaredNamespaceRefLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:foo="urn:foo" targetNamespace="urn:t">
          <xs:import namespace="urn:bar"/>
          <xs:element name="root" type="foo:T"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("names namespace 'urn:foo', which is not the target namespace and is not imported") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }
}
