import Testing
@testable import PureXML

/// The `namespace` constraint of an `any`/`anyAttribute` wildcard (XSD 1.0
/// Structures): `('##any' | '##other')` standing alone, or a list of namespace
/// URIs and the `##targetNamespace`/`##local` tokens. A misspelled token or
/// `##any`/`##other` inside a list is invalid (the W3C wildcard families).
@Suite("Wildcard namespace constraint")
struct SchemaWildcardNamespaceTests {
    private func compile(_ namespace: String) throws {
        _ = try PureXML.Schema.Document(#"""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:complexType name="ct">
            <xs:sequence><xs:any namespace="\#(namespace)"/></xs:sequence>
            <xs:anyAttribute namespace="\#(namespace)"/>
          </xs:complexType>
        </xs:schema>
        """#)
    }

    private func rejects(_ namespace: String) -> Bool {
        do { try compile(namespace)
            return false
        } catch { return true }
    }

    @Test("valid namespace constraints compile")
    func test_valid() throws {
        for namespace in [
            "##any",
            "##other",
            "##targetNamespace",
            "##local",
            "##targetNamespace ##local",
            "urn:a",
            "urn:a urn:b",
            "urn:a ##local ##targetNamespace",
            "",
        ] {
            try compile(namespace)
        }
    }

    @Test("malformed namespace constraints are rejected")
    func test_invalid() {
        for namespace in ["##all", "##target", "##any ##other", "##any ##local", "##other urn:a", "##targetnamespace", "##foo urn:a"] {
            #expect(rejects(namespace), "expected rejection: '\(namespace)'")
        }
    }

    @Test("a foreign-namespace attribute named namespace is not the wildcard constraint")
    func test_foreignNamespaceAttributeIgnored() throws {
        // The unprefixed namespace is valid (##any); the prefixed foo:namespace is
        // the author's own foreign attribute and must not be validated.
        _ = try PureXML.Schema.Document(#"""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:foo="urn:foo">
          <xs:complexType name="ct">
            <xs:sequence><xs:any foo:namespace="##all" namespace="##any"/></xs:sequence>
          </xs:complexType>
        </xs:schema>
        """#)
    }
}
