import Testing
@testable import PureXML

/// Schema compile findings carry validation coding paths that resolve to source
/// spans on a ranged schema tree, the IDE underline flow for #169.
@Suite("Schema located compile diagnostics")
struct SchemaLocatedDiagnosticsTests {
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

    @Test("A duplicate xs:ID is located on the offending component")
    func test_duplicateIdLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="a" id="dup"/>
          <xs:element name="b" id="dup"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let duplicate = try #require(findings.first { $0.reason.contains("duplicate id") })
        #expect(duplicate.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])
        #expect(duplicate.codingPath.last?.intValue == 2)

        let (tree, _) = PureXML.readTree(xsd)
        let range = tree.sourceRange(at: duplicate.codingPath)
        #expect(range?.start.line == 3)
        #expect(range?.start.column == 3)
    }

    @Test("An invalid xs:ID value is located on its declaring component")
    func test_invalidIdLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="a" id="123"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let invalid = try #require(findings.first { $0.reason.contains("not a valid NCName") })
        #expect(invalid.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        let range = tree.sourceRange(at: invalid.codingPath)
        #expect(range?.start.line == 2)
        #expect(range?.start.column == 3)
    }

    @Test("An ID-typed default/fixed value constraint is located on its declaring component")
    func test_idValueConstraintLocated() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="a" type="xs:ID" default="x"/>
        </xs:schema>
        """
        let findings = try inconsistentFindings(in: xsd)
        let located = try #require(findings.first { $0.reason.contains("must not have a default or fixed value") })
        #expect(located.codingPath.map(\.stringValue) == ["xs:schema", "xs:element"])

        let (tree, _) = PureXML.readTree(xsd)
        let range = tree.sourceRange(at: located.codingPath)
        #expect(range?.start.line == 2)
        #expect(range?.start.column == 3)
    }

    @Test("An xs:include targetNamespace mismatch is located on the include directive")
    func test_includeMismatchLocated() throws {
        let included = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:other">
          <xs:element name="e" type="xs:string"/>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:main">
          <xs:include schemaLocation="other.xsd"/>
          <xs:element name="root" type="xs:string"/>
        </xs:schema>
        """
        let findings: [PureXML.Validation.ValidationError]
        do {
            _ = try PureXML.Schema.Document(main, schemaLoader: { $0 == "other.xsd" ? included : nil })
            Issue.record("expected include mismatch to be rejected")
            return
        } catch let error as PureXML.Schema.SchemaError {
            guard case let .inconsistent(found) = error else {
                Issue.record("expected .inconsistent, got \(error)")
                return
            }
            findings = found
        }
        let mismatch = try #require(findings.first { $0.reason.contains("included schema targetNamespace") })
        #expect(mismatch.codingPath.map(\.stringValue) == ["xs:schema", "xs:include"])

        let (tree, _) = PureXML.readTree(main)
        let range = tree.sourceRange(at: mismatch.codingPath)
        #expect(range?.start.line == 2)
        #expect(range?.start.column == 3)
    }

    @Test("SchemaError.inconsistentFindings exposes the validation errors")
    func test_inconsistentFindingsAccessor() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="a" id="123"/>
        </xs:schema>
        """
        do {
            _ = try PureXML.Schema.Document(xsd)
            Issue.record("expected schema compilation to fail")
        } catch let error as PureXML.Schema.SchemaError {
            let findings = try #require(error.inconsistentFindings)
            #expect(findings.contains { $0.reason.contains("not a valid NCName") })
        }
    }
}
