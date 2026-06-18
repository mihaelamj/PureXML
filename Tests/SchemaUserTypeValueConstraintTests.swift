import Testing
@testable import PureXML

@Suite("XSD value constraint valid against a user type (e-props-correct.2 / a-props-correct.2)")
struct SchemaUserTypeValueConstraintTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("A default invalid against a named simpleType's pattern is rejected")
    func test_namedSimpleTypePatternRejected() {
        #expect(!compiles(
            "<xs:element name=\"e\" type=\"answer\" default=\"false\"/>"
                + "<xs:simpleType name=\"answer\"><xs:restriction base=\"xs:boolean\">"
                + "<xs:pattern value=\"true\"/></xs:restriction></xs:simpleType>",
        ))
    }

    @Test("A fixed invalid for a named simpleType restricting a built-in is rejected")
    func test_namedSimpleTypeLexicalRejected() {
        #expect(!compiles(
            "<xs:element name=\"e\" type=\"Float\" fixed=\"1.0F-2\"/>"
                + "<xs:simpleType name=\"Float\"><xs:restriction base=\"xs:float\"/></xs:simpleType>",
        ))
    }

    @Test("A fixed invalid against a complexType's simpleContent base is rejected")
    func test_simpleContentExtensionRejected() {
        #expect(!compiles(
            "<xs:element name=\"e\" type=\"answer\" fixed=\"Yes\"/>"
                + "<xs:complexType name=\"answer\"><xs:simpleContent>"
                + "<xs:extension base=\"xs:boolean\"><xs:attribute name=\"c\" type=\"xs:string\"/>"
                + "</xs:extension></xs:simpleContent></xs:complexType>",
        ))
    }

    @Test("A value valid for its user type compiles")
    func test_validValueAccepted() {
        // Matches the pattern.
        #expect(compiles(
            "<xs:element name=\"e\" type=\"answer\" default=\"true\"/>"
                + "<xs:simpleType name=\"answer\"><xs:restriction base=\"xs:boolean\">"
                + "<xs:pattern value=\"true\"/></xs:restriction></xs:simpleType>",
        ))
        // Valid float.
        #expect(compiles(
            "<xs:element name=\"e\" type=\"Float\" fixed=\"1.0E-2\"/>"
                + "<xs:simpleType name=\"Float\"><xs:restriction base=\"xs:float\"/></xs:simpleType>",
        ))
        // Valid against the simpleContent base.
        #expect(compiles(
            "<xs:element name=\"e\" type=\"answer\" fixed=\"true\"/>"
                + "<xs:complexType name=\"answer\"><xs:simpleContent>"
                + "<xs:extension base=\"xs:boolean\"/></xs:simpleContent></xs:complexType>",
        ))
    }

    /// A value valid for one of a union's member types must compile: the compiled
    /// `SimpleType` validator admits any member, so no special-casing is needed.
    @Test("A value valid for a union member compiles")
    func test_unionMemberAccepted() {
        #expect(compiles(
            "<xs:element name=\"e\" type=\"U\" default=\"7\"/>"
                + "<xs:simpleType name=\"U\"><xs:union memberTypes=\"xs:boolean xs:integer\"/></xs:simpleType>",
        ))
    }

    /// A restriction whose base is an inline `<simpleType>` list must preserve the
    /// list variety, so a `length` facet counts items and a list-valued default of
    /// the right length is valid. Reading the base only from the `base` attribute
    /// dropped the inline list, made the type an atomic string, and counted
    /// characters, wrongly rejecting this schema.
    @Test("A list-valued default on an inline-list-base restriction compiles")
    func test_inlineListBaseRestrictionAccepted() {
        #expect(compiles(
            "<xs:element name=\"e\" type=\"l\" default=\"1 2 3\"/>"
                + "<xs:simpleType name=\"l\"><xs:restriction>"
                + "<xs:simpleType><xs:list itemType=\"xs:integer\"/></xs:simpleType>"
                + "<xs:length value=\"3\"/></xs:restriction></xs:simpleType>",
        ))
        // The same type with a list of the wrong length is still correctly rejected.
        #expect(!compiles(
            "<xs:element name=\"e\" type=\"l\" default=\"1 2\"/>"
                + "<xs:simpleType name=\"l\"><xs:restriction>"
                + "<xs:simpleType><xs:list itemType=\"xs:integer\"/></xs:simpleType>"
                + "<xs:length value=\"3\"/></xs:restriction></xs:simpleType>",
        ))
    }
}
