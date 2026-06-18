import Testing
@testable import PureXML

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

    @Test("An anySimpleType substitution head admits only simple-content members")
    func test_anySimpleTypeHeadRequiresSimpleContentMember() {
        #expect(compiles(
            "<xs:element name=\"head\" type=\"xs:anySimpleType\"/>"
                + "<xs:simpleType name=\"S\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
                + "<xs:complexType name=\"SC\"><xs:simpleContent><xs:extension base=\"xs:string\"/></xs:simpleContent></xs:complexType>"
                + "<xs:element name=\"simple\" substitutionGroup=\"head\" type=\"S\"/>"
                + "<xs:element name=\"simpleContent\" substitutionGroup=\"head\" type=\"SC\"/>",
        ))
        #expect(!compiles(
            "<xs:element name=\"head\" type=\"xs:anySimpleType\"/>"
                + "<xs:complexType name=\"CT\"><xs:sequence><xs:element name=\"e\"/></xs:sequence></xs:complexType>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"CT\"/>",
        ))
        #expect(!compiles(
            "<xs:element name=\"head\" type=\"xs:anySimpleType\"/>"
                + "<xs:complexType name=\"CT\"><xs:attribute name=\"a\"/></xs:complexType>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"CT\"/>",
        ))
        #expect(compiles(
            "<xs:element name=\"head\" type=\"xs:anySimpleType\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\"/>",
        ))
    }

    @Test("An inline anySimpleType substitution member must also have simple content")
    func test_inlineAnySimpleTypeMemberRequiresSimpleContent() {
        #expect(compiles(
            "<xs:element name=\"head\" type=\"xs:anySimpleType\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\">"
                + "<xs:complexType><xs:simpleContent><xs:extension base=\"xs:string\"/></xs:simpleContent></xs:complexType>"
                + "</xs:element>",
        ))
        #expect(!compiles(
            "<xs:element name=\"head\" type=\"xs:anySimpleType\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\">"
                + "<xs:complexType><xs:sequence><xs:element name=\"e\"/></xs:sequence></xs:complexType>"
                + "</xs:element>",
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

    /// With an import but no loader the check stands down; once the import is
    /// loaded through a `schemaLoader` the member type is checked against the head.
    @Test("With an unloaded import the check stands down")
    func test_importWithoutLoaderStandsDown() {
        let main = "<xs:schema \(xsd) xmlns:imp=\"urn:imp\">"
            + "<xs:import namespace=\"urn:imp\" schemaLocation=\"imp.xsd\"/>"
            + "<xs:element name=\"member\" substitutionGroup=\"imp:head\" type=\"xs:int\"/></xs:schema>"
        #expect((try? PureXML.Schema.Document(main)) != nil)
    }

    @Test("With a loaded import an unrelated member type is rejected")
    func test_loadedImportChecksMemberType() {
        let imported = "<xs:schema \(xsd) targetNamespace=\"urn:imp\">"
            + "<xs:element name=\"head\" type=\"xs:string\"/></xs:schema>"
        let main = "<xs:schema \(xsd) xmlns:imp=\"urn:imp\">"
            + "<xs:import namespace=\"urn:imp\" schemaLocation=\"imp.xsd\"/>"
            + "<xs:element name=\"member\" substitutionGroup=\"imp:head\" type=\"xs:int\"/></xs:schema>"
        #expect((try? PureXML.Schema.Document(main, schemaLoader: { $0 == "imp.xsd" ? imported : nil })) == nil)
    }

    @Test("Substitution group member is blocked if type derivation method is final on the head element")
    func test_finalSubstitutionExclusion() {
        // Direct extension derivation rejected when final="extension"
        #expect(!compiles(
            "<xs:complexType name=\"Base\"><xs:sequence/></xs:complexType>"
                + "<xs:complexType name=\"Ext\"><xs:complexContent><xs:extension base=\"Base\"><xs:sequence/></xs:extension></xs:complexContent></xs:complexType>"
                + "<xs:element name=\"head\" type=\"Base\" final=\"extension\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"Ext\"/>",
        ))

        // Direct restriction derivation accepted when final="extension"
        #expect(compiles(
            "<xs:complexType name=\"Base\"><xs:sequence/></xs:complexType>"
                + "<xs:complexType name=\"Res\"><xs:complexContent><xs:restriction base=\"Base\"><xs:sequence/></xs:restriction></xs:complexContent></xs:complexType>"
                + "<xs:element name=\"head\" type=\"Base\" final=\"extension\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"Res\"/>",
        ))

        // Indirect extension derivation rejected when final="extension"
        #expect(!compiles(
            "<xs:complexType name=\"Base\"><xs:sequence/></xs:complexType>"
                + "<xs:complexType name=\"Mid\"><xs:complexContent><xs:extension base=\"Base\"><xs:sequence/></xs:extension></xs:complexContent></xs:complexType>"
                + "<xs:complexType name=\"Derived\"><xs:complexContent><xs:restriction base=\"Mid\"><xs:sequence/></xs:restriction></xs:complexContent></xs:complexType>"
                + "<xs:element name=\"head\" type=\"Base\" final=\"extension\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"Derived\"/>",
        ))

        // Schema finalDefault="extension" rejects extension derivation
        #expect((try? PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" finalDefault="extension">
            <xs:complexType name="Base"><xs:sequence/></xs:complexType>
            <xs:complexType name="Ext"><xs:complexContent><xs:extension base="Base"><xs:sequence/></xs:extension></xs:complexContent></xs:complexType>
            <xs:element name="head" type="Base"/>
            <xs:element name="member" substitutionGroup="head" type="Ext"/>
        </xs:schema>
        """)) == nil)

        // final="#all" rejects both extension and restriction
        #expect(!compiles(
            "<xs:complexType name=\"Base\"><xs:sequence/></xs:complexType>"
                + "<xs:complexType name=\"Ext\"><xs:complexContent><xs:extension base=\"Base\"><xs:sequence/></xs:extension></xs:complexContent></xs:complexType>"
                + "<xs:element name=\"head\" type=\"Base\" final=\"#all\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"Ext\"/>",
        ))
    }

    @Test("Substitution group member final exclusions: local name collisions and built-ins")
    func test_finalSubstitutionExclusionEdgeCases() {
        // Local element name collision: local element does not overwrite global final setting.
        // Base carries an explicit empty final so the schema's finalDefault="extension" (which a
        // complex type also inherits as its {final}) does not itself block Ext's extension of Base;
        // the point under test is that the LOCAL element named "head" inside Ext does not clobber
        // the GLOBAL "head" element's final="restriction".
        #expect((try? PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" finalDefault="extension">
            <xs:element name="head" type="Base" final="restriction"/>
            <xs:element name="member" substitutionGroup="head" type="Ext"/>
            <xs:complexType name="Base" final=""><xs:sequence/></xs:complexType>
            <xs:complexType name="Ext" final="">
                <xs:complexContent>
                    <xs:extension base="Base">
                        <xs:sequence>
                            <xs:element name="head" type="xs:string"/>
                        </xs:sequence>
                    </xs:extension>
                </xs:complexContent>
            </xs:complexType>
        </xs:schema>
        """)) != nil)

        // Built-in simple type restriction rejected when final="restriction"
        #expect(!compiles(
            "<xs:element name=\"head\" type=\"xs:decimal\" final=\"restriction\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\" type=\"xs:int\"/>",
        ))
    }

    @Test("Substitution group member is blocked if inline complexType derivation method is final on the head element")
    func test_finalSubstitutionExclusionInlineType() {
        // Member3 derives by extension from HeadType inline, but Head has final="extension" -> rejected
        #expect(!compiles(
            "<xs:complexType name=\"HeadType\"><xs:sequence/></xs:complexType>"
                + "<xs:element name=\"Head\" type=\"HeadType\" final=\"extension\"/>"
                + "<xs:element name=\"Member3\" substitutionGroup=\"Head\">"
                + "  <xs:complexType><xs:complexContent>"
                + "    <xs:extension base=\"HeadType\"><xs:sequence/></xs:extension>"
                + "  </xs:complexContent></xs:complexType>"
                + "</xs:element>",
        ))

        // Member3 derives by extension from HeadType inline, Head has final="restriction" -> accepted
        #expect(compiles(
            "<xs:complexType name=\"HeadType\"><xs:sequence/></xs:complexType>"
                + "<xs:element name=\"Head\" type=\"HeadType\" final=\"restriction\"/>"
                + "<xs:element name=\"Member3\" substitutionGroup=\"Head\">"
                + "  <xs:complexType><xs:complexContent>"
                + "    <xs:extension base=\"HeadType\"><xs:sequence/></xs:extension>"
                + "  </xs:complexContent></xs:complexType>"
                + "</xs:element>",
        ))
    }

    @Test("Adversarial Critic: member with inline simpleType restricting another type")
    func test_inlineSimpleTypeRestrictingAnotherType() {
        #expect(compiles(
            "<xs:element name=\"head\" type=\"xs:integer\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\">"
                + "  <xs:simpleType>"
                + "    <xs:restriction>"
                + "      <xs:simpleType>"
                + "        <xs:restriction base=\"xs:int\"/>"
                + "      </xs:simpleType>"
                + "    </xs:restriction>"
                + "  </xs:simpleType>"
                + "</xs:element>",
        ))
    }

    @Test("Adversarial Critic: member with inline simpleType restricting a named list type")
    func test_inlineSimpleTypeRestrictingNamedList() {
        #expect(compiles(
            "<xs:simpleType name=\"MyList\"><xs:list itemType=\"xs:int\"/></xs:simpleType>"
                + "<xs:element name=\"head\" type=\"xs:anySimpleType\"/>"
                + "<xs:element name=\"member\" substitutionGroup=\"head\">"
                + "  <xs:simpleType>"
                + "    <xs:restriction base=\"MyList\"/>"
                + "  </xs:simpleType>"
                + "</xs:element>",
        ))
    }
}
