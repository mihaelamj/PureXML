@testable import PureXML
import Testing

@Suite("Schema notation validity tests")
struct SchemaNotationValidityTests {
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

    @Test("Notation must specify public or system attribute")
    func test_notationAttributes() {
        // public only is valid
        #expect(throws: Never.self) {
            try compile(#"""
            <xs:notation name="note1" public="http://example.com/pub1"/>
            """#)
        }

        // system only is valid
        #expect(throws: Never.self) {
            try compile(#"""
            <xs:notation name="note2" system="http://example.com/sys1"/>
            """#)
        }

        // both is valid
        #expect(throws: Never.self) {
            try compile(#"""
            <xs:notation name="note3" public="http://example.com/pub2" system="http://example.com/sys2"/>
            """#)
        }

        // neither is invalid
        #expect(rejects(#"""
        <xs:notation name="note4"/>
        """#))
    }

    @Test("SimpleType notation restriction enumeration check")
    func test_notationEnumeration() {
        // Valid enumeration referencing declared notation
        #expect(throws: Never.self) {
            try compile(#"""
            <xs:notation name="jpeg" public="image/jpeg"/>
            <xs:simpleType name="myNotation">
                <xs:restriction base="xs:NOTATION">
                    <xs:enumeration value="jpeg"/>
                </xs:restriction>
            </xs:simpleType>
            """#)
        }

        // Invalid enumeration referencing undeclared notation
        #expect(rejects(#"""
        <xs:notation name="png" public="image/png"/>
        <xs:simpleType name="myNotation">
            <xs:restriction base="xs:NOTATION">
                <xs:enumeration value="jpeg"/>
            </xs:restriction>
        </xs:simpleType>
        """#))

        // Notation in the XML namespace referenced with xml prefix
        #expect(throws: Never.self) {
            _ = try PureXML.Schema.Document(#"""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                       targetNamespace="http://www.w3.org/XML/1998/namespace">
                <xs:notation name="xmlNotation" public="http://example.com/xml"/>
                <xs:simpleType name="myNotation">
                    <xs:restriction base="xs:NOTATION">
                        <xs:enumeration value="xml:xmlNotation"/>
                    </xs:restriction>
                </xs:simpleType>
            </xs:schema>
            """#)
        }

        // Notation with xmlns="" default namespace unbinding
        #expect(throws: Never.self) {
            _ = try PureXML.Schema.Document(#"""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns="">
                <xs:notation name="jpeg" public="image/jpeg"/>
                <xs:simpleType name="myNotation">
                    <xs:restriction base="xs:NOTATION">
                        <xs:enumeration value="jpeg"/>
                    </xs:restriction>
                </xs:simpleType>
            </xs:schema>
            """#)
        }
    }
}
