import Testing
@testable import PureXML

/// cvc-elt.4.3.2.1 for a list or union `xsi:type`: a list or union simple type
/// derives only from `anySimpleType`, so it can validly stand in only for an
/// element whose declared type is a ur-type. Naming a list or union type on an
/// element of a more specific atomic type is not a valid derivation and is
/// rejected; a genuinely derived (restriction) substitute, or a list/union under
/// an `anySimpleType` declaration, is still accepted.
@Suite("list/union xsi:type derivation")
struct SchemaListUnionXsiTypeTests {
    private func schema(declaredType: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="e" type="\(declaredType)"/>
          <xs:simpleType name="myList"><xs:list itemType="xs:int"/></xs:simpleType>
          <xs:simpleType name="myUnion"><xs:union memberTypes="xs:int xs:string"/></xs:simpleType>
          <xs:simpleType name="myInt"><xs:restriction base="xs:int"><xs:minInclusive value="0"/></xs:restriction></xs:simpleType>
        </xs:schema>
        """)
    }

    private func doc(_ type: String, _ value: String) -> String {
        #"<e xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="\#(type)">\#(value)</e>"#
    }

    @Test("a list or union xsi:type on an int-declared element is rejected")
    func test_listUnionOnAtomicRejected() throws {
        #expect(try !schema(declaredType: "xs:int").validate(doc("myList", "1 2")).isEmpty)
        #expect(try !schema(declaredType: "xs:int").validate(doc("myUnion", "x")).isEmpty)
    }

    @Test("a valid restriction xsi:type on an int-declared element is accepted")
    func test_restrictionAccepted() throws {
        #expect(try schema(declaredType: "xs:int").validate(doc("myInt", "5")).isEmpty)
    }

    @Test("a list or union xsi:type under anySimpleType is accepted")
    func test_listUnionUnderUrTypeAccepted() throws {
        #expect(try schema(declaredType: "xs:anySimpleType").validate(doc("myList", "1 2")).isEmpty)
        #expect(try schema(declaredType: "xs:anySimpleType").validate(doc("myUnion", "x")).isEmpty)
    }

    /// The declared type is resolved through the element-ref chain: a list/union
    /// xsi:type on an element reached via `<xs:element ref>` (whose global
    /// declaration is atomic) is still rejected.
    @Test("a list/union xsi:type on a ref'd atomic element is rejected")
    func test_listUnionOnReferencedAtomicRejected() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root"><xs:complexType><xs:sequence>
            <xs:element ref="leaf"/>
          </xs:sequence></xs:complexType></xs:element>
          <xs:element name="leaf" type="xs:int"/>
          <xs:simpleType name="myList"><xs:list itemType="xs:int"/></xs:simpleType>
        </xs:schema>
        """)
        let xml = #"<root><leaf xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="myList">1 2</leaf></root>"#
        #expect(try !schema.validate(xml).isEmpty)
    }

    /// The not-derived check also covers ATOMIC substitutes recorded in the
    /// backbone: an `xsi:type` naming a sibling type, or the declared type's own
    /// ancestor, is rejected; a genuinely derived restriction is accepted.
    @Test("an atomic xsi:type not derived from the declared type is rejected")
    func test_atomicNotDerivedRejected() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="e" type="A"/>
          <xs:simpleType name="Base"><xs:restriction base="xs:int"/></xs:simpleType>
          <xs:simpleType name="A"><xs:restriction base="Base"><xs:minInclusive value="0"/></xs:restriction></xs:simpleType>
          <xs:simpleType name="Sibling"><xs:restriction base="Base"><xs:maxInclusive value="9"/></xs:restriction></xs:simpleType>
          <xs:simpleType name="Derived"><xs:restriction base="A"><xs:maxInclusive value="9"/></xs:restriction></xs:simpleType>
        </xs:schema>
        """)
        func doc(_ type: String) -> String {
            #"<e xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="\#(type)">5</e>"#
        }
        // A sibling (also restricts Base) is not derived from A: rejected.
        #expect(try !schema.validate(doc("Sibling")).isEmpty)
        // The declared type's own ancestor Base is not derived from A: rejected.
        #expect(try !schema.validate(doc("Base")).isEmpty)
        // A genuine restriction of A is validly derived: accepted.
        #expect(try schema.validate(doc("Derived")).isEmpty)
    }

    /// A complex substitute that records no base of its own derives only from
    /// `anyType`, so it cannot validly substitute for a non-ur complex declared
    /// type: naming the declared type's complex ancestor, or an unrelated baseless
    /// complex type, is rejected; a genuine extension/restriction is accepted.
    @Test("a baseless or ancestor complex xsi:type is rejected, a derived one accepted")
    func test_baselessComplexNotDerivedRejected() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="e" type="Dr"/>
          <xs:complexType name="B"><xs:sequence><xs:element name="f" type="xs:string"/></xs:sequence></xs:complexType>
          <xs:complexType name="Dr"><xs:complexContent><xs:restriction base="B">
            <xs:sequence><xs:element name="f" type="xs:string"/></xs:sequence>
          </xs:restriction></xs:complexContent></xs:complexType>
          <xs:complexType name="Drr"><xs:complexContent><xs:restriction base="Dr">
            <xs:sequence><xs:element name="f" type="xs:string"/></xs:sequence>
          </xs:restriction></xs:complexContent></xs:complexType>
          <xs:complexType name="Other"/>
        </xs:schema>
        """)
        func doc(_ type: String) -> String {
            #"<e xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="\#(type)"><f>x</f></e>"#
        }
        // B is Dr's ancestor (Dr restricts B), not derived from Dr: rejected.
        #expect(try !schema.validate(doc("B")).isEmpty)
        // Other is an unrelated baseless complex type: rejected.
        #expect(try !schema.validate(#"<e xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="Other"/>"#).isEmpty)
        // Drr restricts Dr: validly derived, accepted.
        #expect(try schema.validate(doc("Drr")).isEmpty)
    }

    @Test("xsi:type=anyType cannot substitute for an anySimpleType-declared element")
    func test_anyTypeForAnySimpleType() throws {
        let xsi = "http://www.w3.org/2001/XMLSchema-instance"
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="item" type="xs:anySimpleType"/>
          <xs:element name="root">
            <xs:complexType><xs:sequence><xs:element ref="item" maxOccurs="unbounded"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """)
        func root(_ type: String, _ value: String) -> String {
            #"<root xmlns:xsi="\#(xsi)" xmlns:xs="http://www.w3.org/2001/XMLSchema"><item xsi:type="\#(type)">\#(value)</item></root>"#
        }
        // anyType is anySimpleType's supertype, not derived from it: rejected, for that reason.
        #expect(try schema.validate(root("xs:anyType", "x")).contains { $0.reason.contains("anySimpleType declared type") })
        // anySimpleType (reflexive) and a derived atomic type are valid substitutes.
        #expect(try schema.validate(root("xs:anySimpleType", "x")).isEmpty)
        #expect(try schema.validate(root("xs:int", "123")).isEmpty)
    }
}
