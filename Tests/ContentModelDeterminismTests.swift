import Testing
@testable import PureXML

/// Unique Particle Attribution (cos-nonambig, XSD 1.0 3.8.6): a content model
/// must be deterministic, so each element in an instance is attributable to a
/// single particle without lookahead. The check runs on a literal, QName-resolved
/// view of the raw schema tree (refs are not substitution-group expanded, the
/// overlap test is QName-only), and is per particle: a particle competing with a
/// repetition of itself is never a violation. These cases pin both the rejections
/// and the deterministic shapes that must keep compiling (XSTS valid mgZ005,
/// ctZ008, particlesHa142, groupH001).
@Suite("Content model determinism (UPA)")
struct ContentModelDeterminismTests {
    private func compile(_ body: String) throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        \(body)
        </xs:schema>
        """)
    }

    private func rejects(_ body: String) -> Bool {
        do { try compile(body)
            return false
        } catch { return true }
    }

    private func complexType(_ model: String) -> String {
        #"<xs:complexType name="t">\#(model)</xs:complexType>"#
    }

    // MARK: - Ambiguous models are rejected

    @Test("a choice of two same-name elements is ambiguous")
    func test_choiceOfSameName() {
        #expect(rejects(complexType(#"<xs:choice><xs:element name="a"/><xs:element name="a"/></xs:choice>"#)))
    }

    @Test("an optional element followed by a same-name element is ambiguous")
    func test_optionalThenSameName() {
        #expect(rejects(complexType(#"<xs:sequence><xs:element name="a" minOccurs="0"/><xs:element name="a"/></xs:sequence>"#)))
    }

    @Test("a repeating element followed by a same-name element is ambiguous")
    func test_repeatThenSameName() {
        #expect(rejects(complexType(#"<xs:sequence><xs:element name="a" maxOccurs="unbounded"/><xs:element name="a"/></xs:sequence>"#)))
    }

    @Test("a choice of ##other and an overlapping namespace wildcard is ambiguous")
    func test_choiceOfOtherAndOverlappingWildcard() {
        // `##other` admits namespace A (A is neither absent nor the target), and so
        // does `namespace="A"`, so an A-namespaced element matches both (XSTS wildI009).
        #expect(rejects(complexType("<xs:choice><xs:any namespace='##other'/><xs:any namespace='A'/></xs:choice>")))
    }

    @Test("a choice of two ##other wildcards is ambiguous")
    func test_choiceOfTwoOtherWildcards() {
        #expect(rejects(complexType("<xs:choice><xs:any namespace='##other'/><xs:any namespace='##other'/></xs:choice>")))
    }

    @Test("a choice of ##other and ##local is deterministic and compiles")
    func test_choiceOfOtherAndLocalCompiles() {
        // `##other` never admits the absent namespace and `##local` admits only it,
        // so they are disjoint: the model is deterministic and must not be rejected.
        #expect(!rejects(complexType("<xs:choice><xs:any namespace='##other'/><xs:any namespace='##local'/></xs:choice>")))
    }

    @Test("an extension is checked against its base's effective content model")
    func test_extensionEffectiveModelAmbiguous() {
        // The base's trailing `a*` is followed by the extension's `a`, so an `a`
        // matches either across the extension boundary (XSTS particlesZ022). The
        // check must see the base content prepended, not the extension's own only.
        let body = """
        <xs:complexType name="base"><xs:sequence><xs:element name="a" minOccurs="0" maxOccurs="unbounded"/></xs:sequence></xs:complexType>
        <xs:complexType name="d"><xs:complexContent><xs:extension base="base"><xs:sequence><xs:element name="a"/></xs:sequence></xs:extension></xs:complexContent></xs:complexType>
        """
        #expect(rejects(body))
    }

    @Test("an extension adding distinct content is deterministic and compiles")
    func test_extensionEffectiveModelDeterministic() {
        // base `a` followed by the extension's `b` is `a, b`: deterministic, so
        // prepending the base content must not reject a valid extension.
        let body = """
        <xs:complexType name="base"><xs:sequence><xs:element name="a"/></xs:sequence></xs:complexType>
        <xs:complexType name="d"><xs:complexContent><xs:extension base="base"><xs:sequence><xs:element name="b"/></xs:sequence></xs:extension></xs:complexContent></xs:complexType>
        """
        #expect(!rejects(body))
    }

    @Test("two same-name members of an all group are ambiguous")
    func test_allWithSameName() {
        #expect(rejects(complexType(#"<xs:all><xs:element name="a"/><xs:element name="a"/></xs:all>"#)))
    }

    @Test("an element competing with a wildcard that admits it is ambiguous")
    func test_elementAndWildcard() {
        #expect(rejects(complexType(#"<xs:choice><xs:element name="a"/><xs:any processContents="skip"/></xs:choice>"#)))
    }

    // MARK: - Deterministic models keep compiling

    @Test("distinct elements in sequence and choice are deterministic")
    func test_distinctNames() throws {
        try compile(complexType(#"<xs:sequence><xs:element name="a"/><xs:element name="b" minOccurs="0"/></xs:sequence>"#))
        try compile(complexType(#"<xs:choice><xs:element name="a"/><xs:element name="b"/></xs:choice>"#))
        try compile(complexType(#"<xs:all><xs:element name="a"/><xs:element name="b"/><xs:element name="c"/></xs:all>"#))
    }

    @Test("a fixed-count element followed by a distinct same-name element is deterministic (mgZ005)")
    func test_fixedCountThenSameName() throws {
        try compile(complexType(#"""
        <xs:sequence>
        <xs:element name="a" minOccurs="0"/>
        <xs:element name="b" minOccurs="2" maxOccurs="2"/>
        <xs:element name="b"/>
        </xs:sequence>
        """#))
    }

    @Test("a fixed-count group wrapping a repeating element is deterministic (ctZ008)")
    func test_fixedCountGroupWithRepeat() throws {
        try compile(complexType(#"""
        <xs:sequence minOccurs="2" maxOccurs="2">
        <xs:element name="a" minOccurs="1" maxOccurs="2"/>
        <xs:element name="b" minOccurs="0"/>
        </xs:sequence>
        """#))
    }

    @Test("an element followed by its own optional repeat is deterministic (particlesHa142)")
    func test_elementThenOptionalSameName() throws {
        try compile(complexType(#"""
        <xs:choice>
        <xs:sequence minOccurs="0">
        <xs:element name="a" type="xs:string"/>
        <xs:element name="a" type="xs:string" minOccurs="0"/>
        </xs:sequence>
        </xs:choice>
        """#))
    }

    @Test("a bounded-repeat choice of group references is deterministic (groupH001)")
    func test_repeatedChoiceOfGroups() throws {
        try compile(#"""
        <xs:complexType name="A">
        <xs:choice minOccurs="0" maxOccurs="4">
        <xs:group ref="x"/>
        <xs:group ref="y"/>
        </xs:choice>
        </xs:complexType>
        <xs:group name="x"><xs:sequence><xs:element name="x1"/><xs:element name="x2"/></xs:sequence></xs:group>
        <xs:group name="y"><xs:choice><xs:element name="y1"/><xs:element name="y2"/></xs:choice></xs:group>
        """#)
    }

    // MARK: - Redefine composition

    @Test("a redefine whose self-reference duplicates a particle is ambiguous across documents (schN10)")
    func test_redefineSelfReferenceDuplicatesParticle() {
        // The base declares group g = choice(a, b) and a complex type that uses it.
        // The redefinition expands g to choice(<self-ref to original g>, a): the
        // self-reference brings the original's `a` back, so an `a` is attributable
        // to two particles -> a UPA violation. The ambiguous content model lives in
        // the BASE document's complex type, reached only through the redefined group,
        // so this exercises both the self-reference expansion in the determinism
        // engine and running the UPA check over every composition root.
        let base = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:group name="g"><xs:choice><xs:element name="a" type="xs:int"/><xs:element name="b" type="xs:int"/></xs:choice></xs:group>
          <xs:complexType name="ct"><xs:group ref="g"/></xs:complexType>
          <xs:element name="root" type="ct"/>
        </xs:schema>
        """
        let redefining = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:redefine schemaLocation="base.xsd">
            <xs:group name="g"><xs:choice><xs:group ref="g"/><xs:element name="a" type="xs:int"/></xs:choice></xs:group>
          </xs:redefine>
        </xs:schema>
        """
        let rejected: Bool
        do {
            _ = try PureXML.Schema.Document(redefining, schemaLoader: { $0.hasSuffix("base.xsd") ? base : nil })
            rejected = false
        } catch { rejected = true }
        #expect(rejected)
    }

    @Test("a redefine self-reference that does not duplicate a particle still compiles")
    func test_redefineSelfReferenceWithoutDuplicateCompiles() {
        // Same shape, but the redefinition adds a DISTINCT element `c`, so the
        // expanded model choice(choice(a, b), c) has no overlap and stays valid:
        // the FP-guard for the case above (the change must not over-reject).
        let base = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:group name="g"><xs:choice><xs:element name="a" type="xs:int"/><xs:element name="b" type="xs:int"/></xs:choice></xs:group>
          <xs:complexType name="ct"><xs:group ref="g"/></xs:complexType>
          <xs:element name="root" type="ct"/>
        </xs:schema>
        """
        let redefining = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:redefine schemaLocation="base.xsd">
            <xs:group name="g"><xs:choice><xs:group ref="g"/><xs:element name="c" type="xs:int"/></xs:choice></xs:group>
          </xs:redefine>
        </xs:schema>
        """
        let rejected: Bool
        do {
            _ = try PureXML.Schema.Document(redefining, schemaLoader: { $0.hasSuffix("base.xsd") ? base : nil })
            rejected = false
        } catch { rejected = true }
        #expect(!rejected)
    }
}
