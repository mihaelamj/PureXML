@testable import PureXML
import Testing

@Suite("Adversarial Critic Tests")
struct AdversarialCriticTests {
    @Test("xml prefix on QName references is accepted without explicit xmlns:xml declaration")
    func test_xmlPrefixOnQNameReference() throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:import namespace="http://www.w3.org/XML/1998/namespace"/>
            <xs:element name="myElement">
                <xs:complexType>
                    <xs:attribute ref="xml:lang"/>
                </xs:complexType>
            </xs:element>
        </xs:schema>
        """)
    }

    @Test("foreign elements and attributes inside simpleType restriction are ignored and accepted")
    func test_foreignElementsAndAttributesInSimpleType() throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:simpleType name="mySimple">
                <xs:restriction base="xs:string" ext:customAttr="hello" xmlns:ext="http://example.com/ext">
                    <ext:metadata info="extra"/>
                    <xs:minLength value="1"/>
                </xs:restriction>
            </xs:simpleType>
        </xs:schema>
        """)
    }

    @Test("complex type check with different namespace configurations and prefixes")
    func test_complexTypeCheckNamespaceComplexity() throws {
        // 1. Unprefixed reference to simple type when targetNamespace is default namespace - accepted
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns="http://example.com"
                   targetNamespace="http://example.com">
            <xs:simpleType name="myBaseSimple">
                <xs:restriction base="xs:string"/>
            </xs:simpleType>
            <xs:simpleType name="mySimple">
                <xs:restriction base="myBaseSimple"/>
            </xs:simpleType>
        </xs:schema>
        """)

        // 2. Prefixed reference to simple type - accepted
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns:tns="http://example.com"
                   targetNamespace="http://example.com">
            <xs:simpleType name="myBaseSimple">
                <xs:restriction base="xs:string"/>
            </xs:simpleType>
            <xs:simpleType name="mySimple">
                <xs:restriction base="tns:myBaseSimple"/>
            </xs:simpleType>
        </xs:schema>
        """)

        // 3. Unprefixed reference to simple type in no-targetNamespace schema - accepted
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:simpleType name="myBaseSimple">
                <xs:restriction base="xs:string"/>
            </xs:simpleType>
            <xs:simpleType name="mySimple">
                <xs:restriction base="myBaseSimple"/>
            </xs:simpleType>
        </xs:schema>
        """)

        // 4. Default namespace set to XSD namespace referencing simple/complex types
        _ = try PureXML.Schema.Document("""
        <schema xmlns="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com"
                   xmlns:tns="http://example.com">
            <complexType name="myComplex">
                <sequence>
                    <element name="a" type="string"/>
                </sequence>
            </complexType>
            <simpleType name="mySimple">
                <restriction base="string"/> <!-- restricts xs:string (simple) -->
            </simpleType>
        </schema>
        """)
    }
}
