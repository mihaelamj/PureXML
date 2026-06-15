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

    @Test("schema element order: accepts foreign elements interspersed and before imports/includes/redefines")
    func test_schemaChildrenOrder_foreignElements() throws {
        // 1. Foreign elements before imports
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ext="http://example.com/ext">
            <ext:meta info="1"/>
            <xs:import namespace="http://example.com/other" schemaLocation="some.xsd"/>
            <xs:element name="myElement" type="xs:string"/>
        </xs:schema>
        """)

        // 2. Foreign elements interspersed
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ext="http://example.com/ext">
            <xs:import namespace="http://example.com/other" schemaLocation="some.xsd"/>
            <ext:meta info="1"/>
            <xs:element name="myElement" type="xs:string"/>
        </xs:schema>
        """)

        // 3. Foreign elements with same local names as global declarations (e.g. element/attribute)
        // should not trigger seenDeclaration = true for the schemaChildrenOrderErrors check.
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ext="http://example.com/ext">
            <ext:element name="fake"/>
            <xs:import namespace="http://example.com/other" schemaLocation="some.xsd"/>
            <xs:element name="myElement" type="xs:string"/>
        </xs:schema>
        """)
    }

    @Test("import constraints: valid import cases")
    func test_importConstraints_valid() throws {
        // 1. Importing a namespace with a schema that has a targetNamespace (different from imported namespace)
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="http://example.com/main">
            <xs:import namespace="http://example.com/other" schemaLocation="other.xsd"/>
        </xs:schema>
        """)

        // 2. Importing a namespace with a schema that has NO targetNamespace
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:import namespace="http://example.com/other" schemaLocation="other.xsd"/>
        </xs:schema>
        """)

        // 3. Importing no-namespace schema with a schema that HAS targetNamespace
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="http://example.com/main">
            <xs:import schemaLocation="no-namespace.xsd"/>
        </xs:schema>
        """)
    }
}
