import Testing
@testable import PureXML

@Suite("SimpleType variety constraints")
struct SchemaSimpleTypeVarietyTests {
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

    @Test("itemType cannot be a list or union containing list")
    func test_listItemTypeVariety() {
        // base atomic type is valid
        #expect(throws: Never.self) {
            try compile(#"""
            <xs:simpleType name="L">
                <xs:list itemType="xs:string"/>
            </xs:simpleType>
            """#)
        }

        // list of lists is invalid
        #expect(rejects(#"""
        <xs:simpleType name="L1">
            <xs:list itemType="xs:string"/>
        </xs:simpleType>
        <xs:simpleType name="L2">
            <xs:list itemType="L1"/>
        </xs:simpleType>
        """#))

        // list of union of lists is invalid
        #expect(rejects(#"""
        <xs:simpleType name="L1">
            <xs:list itemType="xs:string"/>
        </xs:simpleType>
        <xs:simpleType name="U1">
            <xs:union memberTypes="xs:integer L1"/>
        </xs:simpleType>
        <xs:simpleType name="L2">
            <xs:list itemType="U1"/>
        </xs:simpleType>
        """#))

        // list of anySimpleType is invalid
        #expect(rejects(#"""
        <xs:simpleType name="L1">
            <xs:list itemType="xs:anySimpleType"/>
        </xs:simpleType>
        """#))
    }

    @Test("inline simpleType child of list cannot be a list or union containing list")
    func test_inlineListVariety() {
        // inline atomic is valid
        #expect(throws: Never.self) {
            try compile(#"""
            <xs:simpleType name="L">
                <xs:list>
                    <xs:simpleType>
                        <xs:restriction base="xs:integer"/>
                    </xs:simpleType>
                </xs:list>
            </xs:simpleType>
            """#)
        }

        // inline list is invalid
        #expect(rejects(#"""
        <xs:simpleType name="L">
            <xs:list>
                <xs:simpleType>
                    <xs:list itemType="xs:string"/>
                </xs:simpleType>
            </xs:list>
        </xs:simpleType>
        """#))
    }

    @Test("nested union of atomic types as list itemType is accepted")
    func test_nestedUnionAtomicListAccepted() throws {
        try compile("""
        <xs:simpleType name="union1">
            <xs:union memberTypes="xs:integer xs:string"/>
        </xs:simpleType>
        <xs:simpleType name="union2">
            <xs:union memberTypes="union1 xs:boolean"/>
        </xs:simpleType>
        <xs:simpleType name="list">
            <xs:list itemType="union2"/>
        </xs:simpleType>
        """)
    }

    @Test("nested union containing a list as list itemType is rejected")
    func test_nestedUnionListRejected() {
        #expect(rejects("""
        <xs:simpleType name="list1">
            <xs:list itemType="xs:integer"/>
        </xs:simpleType>
        <xs:simpleType name="union1">
            <xs:union memberTypes="list1 xs:string"/>
        </xs:simpleType>
        <xs:simpleType name="union2">
            <xs:union memberTypes="union1 xs:boolean"/>
        </xs:simpleType>
        <xs:simpleType name="list2">
            <xs:list itemType="union2"/>
        </xs:simpleType>
        """))
    }

    @Test("foreign itemType reference does not conflate with local list of same name")
    func test_listItemTypeForeignStandDown() throws {
        try compile("""
        <xs:import namespace="http://external.com" schemaLocation="external.xsd"/>
        <xs:simpleType name="myType">
            <xs:list itemType="xs:integer"/>
        </xs:simpleType>
        <xs:simpleType name="list">
            <xs:list itemType="ext:myType" xmlns:ext="http://external.com"/>
        </xs:simpleType>
        """)
    }
}
