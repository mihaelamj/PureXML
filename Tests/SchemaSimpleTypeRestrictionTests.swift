@testable import PureXML
import Testing

@Suite("SimpleType restriction and top-level constraints")
struct SchemaSimpleTypeRestrictionTests {
    private func compile(_ body: String) throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        \(body)
        </xs:schema>
        """)
    }

    private func rejects(_ body: String) -> Bool {
        do {
            try compile(body)
            return false
        } catch {
            return true
        }
    }

    @Test("restricting xs:anySimpleType directly in simpleType is rejected")
    func test_anySimpleTypeRestrictionSimple() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:restriction base="xs:anySimpleType"/>
        </xs:simpleType>
        """))
    }

    @Test("extending xs:anySimpleType under simpleContent is accepted")
    func test_anySimpleTypeSimpleContent() throws {
        try compile("""
        <xs:complexType name="t1">
            <xs:simpleContent>
                <xs:extension base="xs:anySimpleType"/>
            </xs:simpleContent>
        </xs:complexType>
        """)
    }

    @Test("using xs:anySimpleType as list itemType or union memberTypes is accepted")
    func test_anySimpleTypeInListOrUnion() throws {
        try compile("""
        <xs:simpleType name="list">
            <xs:list itemType="xs:anySimpleType"/>
        </xs:simpleType>
        <xs:simpleType name="union">
            <xs:union memberTypes="xs:anySimpleType xs:int"/>
        </xs:simpleType>
        """)
    }

    @Test("top-level anonymous definitions are rejected")
    func test_topLevelUnnamed() {
        #expect(rejects("""
        <xs:simpleType>
            <xs:restriction base="xs:string">
                <xs:pattern value="\\d{5}"/>
            </xs:restriction>
        </xs:simpleType>
        """))
        #expect(rejects("""
        <xs:complexType>
            <xs:sequence>
                <xs:element name="foo" type="xs:string"/>
            </xs:sequence>
        </xs:complexType>
        """))
    }

    @Test("simpleType facet restriction constraints on digits and length are enforced")
    func test_facetRestrictionValidation() throws {
        // totalDigits: base has 4, restriction has 5 -> rejected
        #expect(rejects("""
        <xs:simpleType name="base">
            <xs:restriction base="xs:decimal">
                <xs:totalDigits value="4"/>
            </xs:restriction>
        </xs:simpleType>
        <xs:simpleType name="derived">
            <xs:restriction base="base">
                <xs:totalDigits value="5"/>
            </xs:restriction>
        </xs:simpleType>
        """))

        // totalDigits: base has 4, restriction has 4 -> accepted
        try compile("""
        <xs:simpleType name="base">
            <xs:restriction base="xs:decimal">
                <xs:totalDigits value="4"/>
            </xs:restriction>
        </xs:simpleType>
        <xs:simpleType name="derived">
            <xs:restriction base="base">
                <xs:totalDigits value="4"/>
            </xs:restriction>
        </xs:simpleType>
        """)

        // fractionDigits: base has 2, restriction has 3 -> rejected
        #expect(rejects("""
        <xs:simpleType name="base">
            <xs:restriction base="xs:decimal">
                <xs:fractionDigits value="2"/>
            </xs:restriction>
        </xs:simpleType>
        <xs:simpleType name="derived">
            <xs:restriction base="base">
                <xs:fractionDigits value="3"/>
            </xs:restriction>
        </xs:simpleType>
        """))

        // minLength/maxLength/length restrictions
        #expect(rejects("""
        <xs:simpleType name="base">
            <xs:restriction base="xs:string">
                <xs:minLength value="4"/>
            </xs:restriction>
        </xs:simpleType>
        <xs:simpleType name="derived">
            <xs:restriction base="base">
                <xs:minLength value="3"/>
            </xs:restriction>
        </xs:simpleType>
        """))
    }

    @Test("debug xsd.xsd")
    func test_debugXSD() {
        let path = "/private/tmp/xsts/xmlschema2006-11-06/msData/particles/particlesZ001.xsd"
        if let xml = try? String(contentsOfFile: path) {
            do {
                _ = try PureXML.Schema.Document(xml)
                print("--- particlesZ001.xsd compiled successfully ---")
            } catch {
                print("--- particlesZ001.xsd failed compile: ---")
                print(error)
            }
        }
    }

    @Test("restricting xs:anyType directly in simpleType is rejected")
    func test_anyTypeRestrictionSimple() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:restriction base="xs:anyType"/>
        </xs:simpleType>
        """))
    }

    @Test("unbound QName prefix in simpleType restriction base is rejected")
    func test_unboundPrefixRestrictionBase() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:restriction base="foo:string"/>
        </xs:simpleType>
        """))
    }

    @Test("unbound QName prefix in list itemType is rejected")
    func test_unboundPrefixListItemType() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:list itemType="foo:integer"/>
        </xs:simpleType>
        """))
    }

    @Test("multiple inline simpleType base definitions in restriction is rejected")
    func test_multipleInlineSimpleTypeRestriction() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:restriction>
                <xs:simpleType>
                    <xs:restriction base="xs:string"/>
                </xs:simpleType>
                <xs:simpleType>
                    <xs:restriction base="xs:integer"/>
                </xs:simpleType>
            </xs:restriction>
        </xs:simpleType>
        """))
    }

    @Test("both base attribute and inline simpleType in restriction is rejected")
    func test_baseAndInlineSimpleTypeRestriction() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:restriction base="xs:string">
                <xs:simpleType>
                    <xs:restriction base="xs:string"/>
                </xs:simpleType>
            </xs:restriction>
        </xs:simpleType>
        """))
    }

    @Test("anyAttribute inside simpleType restriction is rejected")
    func test_anyAttributeInSimpleTypeRestriction() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:restriction base="xs:integer">
                <xs:anyAttribute processContents="lax"/>
            </xs:restriction>
        </xs:simpleType>
        """))
    }

    @Test("list with multiple inline simpleTypes is rejected")
    func test_listWithMultipleInlineSimpleTypes() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:list>
                <xs:simpleType>
                    <xs:restriction base="xs:integer"/>
                </xs:simpleType>
                <xs:simpleType>
                    <xs:restriction base="xs:string"/>
                </xs:simpleType>
            </xs:list>
        </xs:simpleType>
        """))
    }

    @Test("list with both itemType and inline simpleType is rejected")
    func test_listWithItemTypeAndInlineSimpleType() {
        #expect(rejects("""
        <xs:simpleType name="t1">
            <xs:list itemType="xs:integer">
                <xs:simpleType>
                    <xs:restriction base="xs:integer"/>
                </xs:simpleType>
            </xs:list>
        </xs:simpleType>
        """))
    }

    @Test("list itemType referencing a complex type is rejected")
    func test_listItemTypeComplexType() {
        #expect(rejects("""
        <xs:complexType name="myComplex">
            <xs:simpleContent>
                <xs:extension base="xs:string"/>
            </xs:simpleContent>
        </xs:complexType>
        <xs:simpleType name="t1">
            <xs:list itemType="myComplex"/>
        </xs:simpleType>
        """))
    }
}
