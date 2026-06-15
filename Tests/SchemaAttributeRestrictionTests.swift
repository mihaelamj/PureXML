@testable import PureXML
import Testing

@Suite("XSD attribute-use restriction (cos-ct-derived-ok)")
struct SchemaAttributeRestrictionTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    private func derive(base: String, restricted: String) -> String {
        "<xs:complexType name=\"Base\">\(base)</xs:complexType>"
            + "<xs:complexType name=\"D\"><xs:complexContent><xs:restriction base=\"Base\">"
            + "\(restricted)</xs:restriction></xs:complexContent></xs:complexType>"
    }

    @Test("A restriction may not relax a required attribute")
    func test_requiredRelaxationRejected() {
        let req = "<xs:attribute name=\"a\" type=\"xs:string\" use=\"required\"/>"
        // required -> optional (explicit)
        #expect(!compiles(derive(base: req, restricted: "<xs:attribute name=\"a\" type=\"xs:string\" use=\"optional\"/>")))
        // required -> optional (default use)
        #expect(!compiles(derive(base: req, restricted: "<xs:attribute name=\"a\" type=\"xs:string\"/>")))
        // required -> prohibited
        #expect(!compiles(derive(base: req, restricted: "<xs:attribute name=\"a\" type=\"xs:string\" use=\"prohibited\"/>")))
    }

    @Test("A faithful or tightening attribute restriction compiles")
    func test_validRestrictionsAccepted() {
        // required kept required
        let req = "<xs:attribute name=\"a\" type=\"xs:string\" use=\"required\"/>"
        #expect(compiles(derive(base: req, restricted: req)))
        // fixed kept identical
        let fixed = "<xs:attribute name=\"a\" type=\"xs:string\" fixed=\"x\"/>"
        #expect(compiles(derive(base: fixed, restricted: "<xs:attribute name=\"a\" type=\"xs:string\" fixed=\"x\"/>")))
        // optional base may be made prohibited or stay optional
        let opt = "<xs:attribute name=\"a\" type=\"xs:string\"/>"
        #expect(compiles(derive(base: opt, restricted: "<xs:attribute name=\"a\" type=\"xs:string\" use=\"prohibited\"/>")))
        // an attribute the restriction does not redeclare is inherited unchanged
        #expect(compiles(derive(base: req, restricted: "")))
        // an optional base attribute that is also fixed may be prohibited (the
        // prohibited use removes it, so the fixed clause does not apply).
        #expect(compiles(derive(base: fixed, restricted: "<xs:attribute name=\"a\" type=\"xs:string\" use=\"prohibited\"/>")))
    }

    /// The fixed-value clause is a disclosed under-rejection (it needs value-space,
    /// not lexical, comparison). A list-typed fixed value that differs only in
    /// whitespace is the same value and must compile; and, for now, even a genuinely
    /// changed fixed value is accepted rather than risk a lexical false positive.
    @Test("Fixed-value differences on a restricted attribute: matching values compile, mismatched values are rejected")
    func test_fixedClauseRestrictions() {
        let listBase = "<xs:simpleType name=\"L\"><xs:list itemType=\"xs:int\"/></xs:simpleType>"
            + "<xs:complexType name=\"Base\"><xs:attribute name=\"a\" type=\"L\" fixed=\"1   2  3\"/></xs:complexType>"

        // Same list value, different whitespace: valid, must compile.
        let derivedValidWS = "<xs:complexType name=\"D\"><xs:complexContent><xs:restriction base=\"Base\">"
            + "<xs:attribute name=\"a\" type=\"L\" fixed=\"1 2 3\"/></xs:restriction></xs:complexContent></xs:complexType>"
        #expect(compiles(listBase + derivedValidWS))

        // Same integer values, different padding: valid, must compile.
        let intBase = "<xs:complexType name=\"Base\"><xs:attribute name=\"a\" type=\"xs:integer\" fixed=\"01\"/></xs:complexType>"
        let derivedValidInt = "<xs:complexType name=\"D\"><xs:complexContent><xs:restriction base=\"Base\">"
            + "<xs:attribute name=\"a\" type=\"xs:integer\" fixed=\"1\"/></xs:restriction></xs:complexContent></xs:complexType>"
        #expect(compiles(intBase + derivedValidInt))

        // Mismatched list values: invalid, must be rejected.
        let derivedInvalidList = "<xs:complexType name=\"D\"><xs:complexContent><xs:restriction base=\"Base\">"
            + "<xs:attribute name=\"a\" type=\"L\" fixed=\"1 2 4\"/></xs:restriction></xs:complexContent></xs:complexType>"
        #expect(!compiles(listBase + derivedInvalidList))

        // Mismatched integer values: invalid, must be rejected.
        let derivedInvalidInt = "<xs:complexType name=\"D\"><xs:complexContent><xs:restriction base=\"Base\">"
            + "<xs:attribute name=\"a\" type=\"xs:integer\" fixed=\"2\"/></xs:restriction></xs:complexContent></xs:complexType>"
        #expect(!compiles(intBase + derivedInvalidInt))

        // Missing value constraint when base is fixed: invalid, must be rejected.
        let derivedMissingConstraint = "<xs:complexType name=\"D\"><xs:complexContent><xs:restriction base=\"Base\">"
            + "<xs:attribute name=\"a\" type=\"xs:integer\"/></xs:restriction></xs:complexContent></xs:complexType>"
        #expect(!compiles(intBase + derivedMissingConstraint))

        // Default value constraint when base is fixed: invalid, must be rejected.
        let derivedDefaultConstraint = "<xs:complexType name=\"D\"><xs:complexContent><xs:restriction base=\"Base\">"
            + "<xs:attribute name=\"a\" type=\"xs:integer\" default=\"1\"/></xs:restriction></xs:complexContent></xs:complexType>"
        #expect(!compiles(intBase + derivedDefaultConstraint))
    }

    @Test("A restriction may not change an attribute's type to a non-derived type")
    func test_attributeTypeRestriction() {
        let base = "<xs:attribute name=\"a\" type=\"xs:integer\"/>"
        // integer -> string (unrelated): invalid
        #expect(!compiles(derive(base: base, restricted: "<xs:attribute name=\"a\" type=\"xs:string\"/>")))
        // integer -> int (valid restriction): valid
        #expect(compiles(derive(base: base, restricted: "<xs:attribute name=\"a\" type=\"xs:int\"/>")))
        // integer -> union(float, integer): invalid
        let unionDef = "<xs:simpleType name=\"U\"><xs:union memberTypes=\"xs:float xs:integer\"/></xs:simpleType>"
        #expect(!compiles(unionDef + derive(base: base, restricted: "<xs:attribute name=\"a\" type=\"U\"/>")))
    }

    @Test("Restricting an untyped (anySimpleType) attribute to list and union types is valid")
    func test_anySimpleTypeRestrictedToListAndUnion() {
        let base = "<xs:attribute name=\"a\"/>" // untyped, defaults to xs:anySimpleType
        // anySimpleType -> atomic (xs:integer): valid
        #expect(compiles(derive(base: base, restricted: "<xs:attribute name=\"a\" type=\"xs:integer\"/>")))
        // anySimpleType -> list (xs:NMTOKENS): valid
        #expect(compiles(derive(base: base, restricted: "<xs:attribute name=\"a\" type=\"xs:NMTOKENS\"/>")))
        // anySimpleType -> union: valid
        let unionDef = "<xs:simpleType name=\"U\"><xs:union memberTypes=\"xs:integer xs:string\"/></xs:simpleType>"
        #expect(compiles(unionDef + derive(base: base, restricted: "<xs:attribute name=\"a\" type=\"U\"/>")))
    }
}
