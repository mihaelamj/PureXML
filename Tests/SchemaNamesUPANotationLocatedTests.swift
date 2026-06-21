import Testing
@testable import PureXML

/// Names/UPA/notation-pass schema compile findings (component-name uniqueness,
/// identity-constraint name uniqueness, keyref `refer` resolution, Unique Particle
/// Attribution, and notation validity) carry validation coding paths that resolve
/// to source spans, the IDE underline flow for #169. Split from the other
/// located-diagnostics suites to keep each suite within the type-body length budget.
@Suite("Schema names/UPA/notation-pass located compile diagnostics")
struct SchemaNamesUPANotationLocatedTests {
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

    @Test("A duplicate global type name is located on the second declaration")
    func test_duplicateGlobalLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="t"><xs:sequence/></xs:complexType>
          <xs:complexType name="t"><xs:sequence/></xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("duplicate type name 't'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }

    @Test("A duplicate identity-constraint name is located on the second constraint")
    func test_duplicateIdentityConstraintLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root">
            <xs:complexType><xs:sequence><xs:element name="c" type="xs:string"/></xs:sequence></xs:complexType>
            <xs:key name="dup"><xs:selector xpath="c"/><xs:field xpath="."/></xs:key>
            <xs:unique name="dup"><xs:selector xpath="c"/><xs:field xpath="."/></xs:unique>
          </xs:element>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("duplicate identity constraint name 'dup'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element", "xs:unique"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 5)
    }

    @Test("A keyref to an undeclared key is located on the keyref")
    func test_keyrefUndeclaredLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root">
            <xs:complexType><xs:sequence/></xs:complexType>
            <xs:keyref name="kr" refer="nope"><xs:selector xpath="."/><xs:field xpath="@a"/></xs:keyref>
          </xs:element>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("keyref refers to undeclared key or unique 'nope'") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element", "xs:keyref"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 4)
    }

    @Test("A UPA violation is located on the ambiguous content model")
    func test_upaViolationLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="t">
            <xs:choice>
              <xs:element name="a" type="xs:string"/>
              <xs:element name="a" type="xs:int"/>
            </xs:choice>
          </xs:complexType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("deterministic") || $0.reason.contains("ambiguous") || $0.reason.contains("Unique Particle") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:complexType", "xs:choice"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 3)
    }

    @Test("A notation missing public and system is located on the notation")
    func test_notationMissingAttributesLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:notation name="n"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("must specify at least one of public or system") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:notation"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 2)
    }

    @Test("A notation enumeration naming no declared notation is located on the enumeration")
    func test_notationEnumerationLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:notation name="n" system="x"/>
          <xs:simpleType name="t">
            <xs:restriction base="xs:NOTATION">
              <xs:enumeration value="undeclared"/>
            </xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("notation enumeration value 'undeclared' does not name a declared notation") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:simpleType", "xs:restriction", "xs:enumeration"])

        let (tree, _) = PureXML.readTree(xsd)
        #expect(tree.sourceRange(at: located.codingPath)?.start.line == 5)
    }
}
