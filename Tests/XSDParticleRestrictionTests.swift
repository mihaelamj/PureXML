@testable import PureXML
import Testing

@Suite("XSD Particle Valid (Restriction)")
struct XSDParticleRestrictionTests {
    private let xsNamespace = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func schema(base: String, restriction: String) -> String {
        """
        <xs:schema \(xsNamespace)>
          <xs:complexType name="B">\(base)</xs:complexType>
          <xs:complexType name="R">
            <xs:complexContent><xs:restriction base="B">\(restriction)</xs:restriction></xs:complexContent>
          </xs:complexType>
          <xs:element name="r" type="R"/>
        </xs:schema>
        """
    }

    private func compiles(base: String, restriction: String) -> Bool {
        (try? PureXML.Schema.Document(schema(base: base, restriction: restriction))) != nil
    }

    private func restrictionError(base: String, restriction: String) -> String? {
        do {
            _ = try PureXML.Schema.Document(schema(base: base, restriction: restriction))
            return nil
        } catch let error as PureXML.Schema.SchemaError {
            return String(describing: error)
        } catch {
            return String(describing: error)
        }
    }

    @Test("Valid restrictions compile: drop an optional, narrow a choice, keep order")
    func test_validRestrictions() {
        // Dropping an optional element.
        #expect(compiles(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/><xs:element name=\"b\" type=\"xs:string\" minOccurs=\"0\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
        ))
        // Narrowing a choice to one branch.
        #expect(compiles(
            base: "<xs:choice><xs:element name=\"a\" type=\"xs:string\"/><xs:element name=\"b\" type=\"xs:string\"/></xs:choice>",
            restriction: "<xs:choice><xs:element name=\"a\" type=\"xs:string\"/></xs:choice>",
        ))
        // Narrowing an occurrence range.
        #expect(compiles(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\" minOccurs=\"0\" maxOccurs=\"unbounded\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\" maxOccurs=\"2\"/></xs:sequence>",
        ))
    }

    @Test("A restriction widening the occurrence range is rejected")
    func test_wideningOccurrenceRejected() {
        let error = restrictionError(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\" maxOccurs=\"2\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\" maxOccurs=\"unbounded\"/></xs:sequence>",
        )
        #expect(error?.contains("not a valid restriction") == true, "\(String(describing: error))")
    }

    @Test("A restriction introducing a new element name is rejected")
    func test_newNameRejected() {
        let error = restrictionError(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"z\" type=\"xs:string\"/></xs:sequence>",
        )
        #expect(error?.contains("not a valid restriction") == true)
    }

    @Test("A restriction reordering a sequence is rejected")
    func test_reorderRejected() {
        let error = restrictionError(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/><xs:element name=\"b\" type=\"xs:string\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"b\" type=\"xs:string\"/><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
        )
        #expect(error?.contains("not a valid restriction") == true)
    }

    @Test("Restricting to empty requires an emptiable base")
    func test_emptyRestriction() {
        // Emptiable base: fine.
        #expect(compiles(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\" minOccurs=\"0\"/></xs:sequence>",
            restriction: "",
        ))
        // Required base content: rejected.
        let error = restrictionError(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
            restriction: "",
        )
        #expect(error?.contains("cannot be EMPTY") == true, "\(String(describing: error))")
    }

    @Test("An element restricts a wildcard only when its namespace is admitted")
    func test_wildcardRestriction() {
        // ##any admits the unqualified element.
        #expect(compiles(
            base: "<xs:sequence><xs:any processContents=\"lax\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
        ))
        // ##other refuses an unqualified element.
        let error = restrictionError(
            base: "<xs:sequence><xs:any namespace=\"##other\" processContents=\"lax\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
        )
        #expect(error?.contains("not a valid restriction") == true)
    }

    @Test("Conformance: the restriction corpus passes through the harness")
    func test_conformanceCases() {
        let valid = compiles(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\" minOccurs=\"0\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
        )
        let invalid = compiles(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/><xs:element name=\"b\" type=\"xs:string\"/></xs:sequence>",
        )
        let cases = [
            PureXML.Validation.ConformanceCase(name: "faithful-restriction-accepted", actual: valid ? "valid" : "invalid", expected: "valid"),
            PureXML.Validation.ConformanceCase(name: "additive-restriction-rejected", actual: invalid ? "valid" : "invalid", expected: "invalid"),
        ]
        let failures = PureXML.Validation.Conformance.failures(in: cases)
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }

    @Test("NameAndTypeOK: a same-name element must keep a type that derives from the base's")
    func test_elementTypeDerivation() {
        // Renaming the element's type to an incompatible one (string -> int) is not a
        // valid restriction: int does not derive from string.
        #expect(!compiles(
            base: "<xs:choice><xs:element name=\"c1\" type=\"xs:string\"/><xs:element name=\"c2\"/></xs:choice>",
            restriction: "<xs:choice><xs:element name=\"c1\" type=\"xs:int\"/><xs:element name=\"c2\"/></xs:choice>",
        ))
        // Narrowing to a derived type (integer -> int) is valid.
        #expect(compiles(
            base: "<xs:choice><xs:element name=\"c1\" type=\"xs:integer\"/><xs:element name=\"c2\"/></xs:choice>",
            restriction: "<xs:choice><xs:element name=\"c1\" type=\"xs:int\"/><xs:element name=\"c2\"/></xs:choice>",
        ))
        // Keeping the same type is valid.
        #expect(compiles(
            base: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
            restriction: "<xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence>",
        ))
    }

    @Test("NameAndTypeOK: widening a concrete-typed element to the ur-type is rejected")
    func test_elementUrTypeWidening() {
        // Restricting a string element to anyType/anySimpleType is widening, invalid.
        #expect(!compiles(
            base: "<xs:choice><xs:element name=\"c1\" type=\"xs:string\"/><xs:element name=\"c2\"/></xs:choice>",
            restriction: "<xs:choice><xs:element name=\"c1\" type=\"xs:anyType\"/><xs:element name=\"c2\"/></xs:choice>",
        ))
        #expect(!compiles(
            base: "<xs:choice><xs:element name=\"c1\" type=\"xs:string\"/><xs:element name=\"c2\"/></xs:choice>",
            restriction: "<xs:choice><xs:element name=\"c1\" type=\"xs:anySimpleType\"/><xs:element name=\"c2\"/></xs:choice>",
        ))
        // The reverse (base is the ur-type, restriction narrows it) is valid.
        #expect(compiles(
            base: "<xs:choice><xs:element name=\"c1\" type=\"xs:anyType\"/><xs:element name=\"c2\"/></xs:choice>",
            restriction: "<xs:choice><xs:element name=\"c1\" type=\"xs:string\"/><xs:element name=\"c2\"/></xs:choice>",
        ))
        // A user type whose local name is "anyType" (not the XSD ur-type) must not be
        // mistaken for it: this is a valid same-type restriction.
        #expect((try? PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t" xmlns:t="urn:t">
          <xs:simpleType name="anyType"><xs:restriction base="xs:string"/></xs:simpleType>
          <xs:complexType name="B"><xs:choice><xs:element name="c1" type="t:anyType"/></xs:choice></xs:complexType>
          <xs:complexType name="R"><xs:complexContent><xs:restriction base="t:B">
            <xs:choice><xs:element name="c1" type="t:anyType"/></xs:choice>
          </xs:restriction></xs:complexContent></xs:complexType>
        </xs:schema>
        """)) != nil)
    }
}
