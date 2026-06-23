import Testing
@testable import PureXML

/// XSD 1.0 (Errata E1-10) cos-ct-extends / src-ct.5: a complexContent extension's
/// {attribute wildcard} is the wildcard UNION of the extension's own attribute
/// wildcard and the base type's. Both `not` namespace-constraint forms exclude
/// absent, so a union admitting "every namespace except a name, plus absent" has
/// no expressible form and the schema is invalid. The expressible unions must be
/// computed correctly (the FP-guard) and the inexpressible one rejected (XSTS
/// wildZ013 / test328873i and the test328873a/d instances).
@Suite("Attribute wildcard union expressibility (Errata E1-10)")
struct SchemaWildcardUnionExpressibilityTests {
    private typealias Wild = PureXML.Schema.Wildcard
    private typealias NSpace = PureXML.Schema.WildcardNamespace

    @Test("E1-10 union of not(a) with a set follows rule 5.1")
    func test_unionNotWithSet() {
        // 5.1.3: set excludes the negated name but includes absent -> NOT expressible.
        #expect(Wild.unionNamespace(.notNamespace("a"), .enumerated(["", "b", "c"])) == nil)
        // 5.1.1: set includes both the name and absent -> any.
        #expect(Wild.unionNamespace(.notNamespace("a"), .enumerated(["a", "", "b"])) == NSpace.any)
        // 5.1.2: set includes the name, not absent -> not(absent).
        #expect(Wild.unionNamespace(.notNamespace("a"), .enumerated(["a", "b"])) == NSpace.notAbsent)
        // 5.1.4: set includes neither -> unchanged not(a).
        #expect(Wild.unionNamespace(.notNamespace("a"), .enumerated(["b", "c"])) == NSpace.notNamespace("a"))
    }

    @Test("E1-10 intersection of two not forms")
    func test_intersectNotForms() {
        // Different negated names: the true not({a,b}) is not expressible (src-ct.4,
        // a deferred rule); to avoid over-rejecting valid cross-namespace attributes
        // on an accepted schema, intersection stays lenient (not(lhs)).
        #expect(Wild.intersectNamespace(.notNamespace("a"), .notNamespace("b")) == NSpace.notNamespace("a"))
        // Same negated name is unchanged.
        #expect(Wild.intersectNamespace(.notNamespace("a"), .notNamespace("a")) == NSpace.notNamespace("a"))
        // not(a) and not(absent) -> named except a.
        #expect(Wild.intersectNamespace(.notNamespace("a"), .notAbsent) == NSpace.notNamespace("a"))
    }

    /// FP-guard (the critic's case): a type intersecting its own `##other` with an
    /// imported attribute group's `##other` (different target namespaces) must still
    /// admit an attribute in a THIRD namespace that both `##other`s allow, not drop
    /// the wildcard. src-ct.4 (intersection not expressible) is a deferred rule, so
    /// the schema is accepted and the lenient wildcard must not over-reject.
    @Test("cross-namespace ##other intersection stays lenient, not dropped")
    func test_crossNamespaceOtherIntersection() throws {
        let imported = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:b" xmlns="urn:b">
          <xs:attributeGroup name="g"><xs:anyAttribute namespace="##other" processContents="skip"/></xs:attributeGroup>
        </xs:schema>
        """
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:a" xmlns:a="urn:a" xmlns:b="urn:b">
          <xs:import namespace="urn:b" schemaLocation="b.xsd"/>
          <xs:element name="doc"><xs:complexType>
            <xs:attributeGroup ref="b:g"/>
            <xs:anyAttribute namespace="##other" processContents="skip"/>
          </xs:complexType></xs:element>
        </xs:schema>
        """, schemaLoader: { _ in imported })
        // urn:c is admitted by not(urn:a) AND not(urn:b): must NOT be rejected.
        #expect(try schema.validate(#"<doc xmlns="urn:a" xmlns:c="urn:c" c:x="1"/>"#).isEmpty)
    }

    /// XSTS wildZ013 (test328873i): `##other` extended with `##local b c` unions to
    /// "everything except the target, plus absent" -> not expressible -> invalid.
    @Test("an extension with a not-expressible attribute-wildcard union is rejected")
    func test_notExpressibleUnionRejected() {
        #expect(throws: (any Error).self) {
            _ = try PureXML.Schema.Document("""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="a" xmlns:a="a">
              <xs:complexType name="base2"><xs:sequence/>
                <xs:anyAttribute namespace="##other" processContents="skip"/>
              </xs:complexType>
              <xs:complexType name="derived2">
                <xs:complexContent><xs:extension base="a:base2">
                  <xs:sequence/><xs:anyAttribute namespace="##local b c" processContents="skip"/>
                </xs:extension></xs:complexContent>
              </xs:complexType>
              <xs:element name="doc" type="a:derived2"/>
            </xs:schema>
            """)
        }
    }

    /// FP-guard: `##other` extended with `##targetNamespace b c` unions to not(absent)
    /// (rule 5.1.2), which IS expressible, so the schema is valid and the resulting
    /// wildcard admits a named attribute but not a no-namespace one.
    @Test("an expressible union compiles and is applied correctly")
    func test_expressibleUnionCompilesAndApplies() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="a" xmlns:a="a">
          <xs:complexType name="base2"><xs:sequence/>
            <xs:anyAttribute namespace="##other" processContents="skip"/>
          </xs:complexType>
          <xs:complexType name="derived2">
            <xs:complexContent><xs:extension base="a:base2">
              <xs:sequence/><xs:anyAttribute namespace="##targetNamespace b c" processContents="skip"/>
            </xs:extension></xs:complexContent>
          </xs:complexType>
          <xs:element name="doc" type="a:derived2"/>
        </xs:schema>
        """)
        // not(absent): a named (urn:b) attribute is admitted...
        #expect(try schema.validate(#"<doc xmlns="a" xmlns:b="b" b:x="1"/>"#).isEmpty)
        // ...but a no-namespace (absent) attribute is rejected.
        #expect(try !schema.validate(#"<doc xmlns="a" y="1"/>"#).isEmpty)
    }
}
