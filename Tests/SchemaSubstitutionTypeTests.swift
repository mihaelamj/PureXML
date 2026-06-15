@testable import PureXML
import Testing

@Suite("XSD substitution-group member type derivation (e-props-correct.4)")
struct SchemaSubstitutionTypeTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("A member whose type is unrelated to the head's type is rejected")
    func test_unrelatedMemberType() {
        #expect(!compiles(
            "<xs:element name=\"head\" type=\"xs:string\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"xs:int\"/>",
        ))
    }

    @Test("A member whose type equals or derives from the head's type is accepted")
    func test_derivingMemberType() {
        // Identical type.
        #expect(compiles(
            "<xs:element name=\"head\" type=\"xs:string\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"xs:string\"/>",
        ))
        // Built-in lattice: xs:int derives from xs:integer.
        #expect(compiles(
            "<xs:element name=\"head\" type=\"xs:integer\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"xs:int\"/>",
        ))
        // User restriction chain.
        #expect(compiles(
            "<xs:simpleType name=\"Small\"><xs:restriction base=\"xs:int\"/></xs:simpleType>"
                + "<xs:element name=\"head\" type=\"xs:int\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"Small\"/>",
        ))
    }

    @Test("An untyped head admits any member type")
    func test_untypedHeadIsUrType() {
        #expect(compiles(
            "<xs:element name=\"head\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"xs:int\"/>",
        ))
    }

    /// `cos-st-derived-ok` clause 2.4: a type validly derives from a union when it
    /// derives from one of the union's member types. List/union derivation is not
    /// modelled, so the check stands down: an integer member of a union-typed head
    /// must compile rather than be wrongly rejected.
    @Test("A member of a union-typed head is not rejected (list/union stand-down)")
    func test_unionTypedHeadStandsDown() {
        #expect(compiles(
            "<xs:simpleType name=\"U\"><xs:union memberTypes=\"xs:float xs:integer\"/></xs:simpleType>"
                + "<xs:element name=\"head\" type=\"U\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"xs:integer\"/>",
        ))
    }

    /// A local element sharing the member's name carries a different type; the
    /// member's type must be read from its own declaration, not conflated with the
    /// local one, so this valid schema compiles.
    @Test("A local element sharing the member name does not supply the member type")
    func test_localNameDoesNotShadowMemberType() {
        #expect(compiles(
            "<xs:element name=\"head\" type=\"xs:boolean\"/>"
                + "<xs:element name=\"foo\" substitutionGroup=\"head\" type=\"xs:boolean\"/>"
                + "<xs:element name=\"root\"><xs:complexType><xs:choice>"
                + "<xs:element ref=\"head\"/>"
                + "<xs:element name=\"foo\" type=\"xs:int\"/>"
                + "</xs:choice></xs:complexType></xs:element>",
        ))
    }

    /// A self-contained schema is required: with an import the head's type may live
    /// in an unloaded document, so the check stands down and a genuinely-unrelated
    /// member is not flagged here (a disclosed under-rejection).
    @Test("With an import present the check stands down")
    func test_importStandsDown() {
        let imported = "<xs:schema \(xsd) targetNamespace=\"urn:imp\">"
            + "<xs:element name=\"head\" type=\"xs:string\"/></xs:schema>"
        let main = "<xs:schema \(xsd) xmlns:imp=\"urn:imp\">"
            + "<xs:import namespace=\"urn:imp\" schemaLocation=\"imp.xsd\"/>"
            + "<xs:element name=\"member\" substitutionGroup=\"imp:head\" type=\"xs:int\"/></xs:schema>"
        #expect((try? PureXML.Schema.Document(main, schemaLoader: { $0 == "imp.xsd" ? imported : nil })) != nil)
    }
}
