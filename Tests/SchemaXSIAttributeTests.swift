import Testing
@testable import PureXML

/// XSD 1.0 Schema Component Constraint "xsi: Not Allowed" (#183): an attribute
/// declaration's {target namespace} must not be the XSI namespace. A schema may
/// target XSI and declare unqualified attributes (they land in no namespace), but a
/// top-level or qualified attribute would land in XSI and is forbidden. Mirrors
/// corpus attKb018a (invalid) against attKb018 / attKc018 (valid).
@Suite("XSD xsi: Not Allowed for attribute declarations (#183)")
struct SchemaXSIAttributeTests {
    private let xsi = "http://www.w3.org/2001/XMLSchema-instance"

    private func compiles(_ schema: String) -> Bool {
        (try? PureXML.Schema.Document(schema)) != nil
    }

    @Test("attKb018a: attributeFormDefault=qualified forces attributes into XSI: rejected")
    func test_qualifiedAttributeIntoXSIRejected() {
        let schema = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                    targetNamespace="\(xsi)" xmlns:x="\(xsi)" attributeFormDefault="qualified">
          <xsd:attributeGroup name="attG">
            <xsd:attribute name="aga1"/>
            <xsd:attribute name="aga2"/>
          </xsd:attributeGroup>
          <xsd:complexType name="attRef">
            <xsd:attributeGroup ref="x:attG"/>
          </xsd:complexType>
          <xsd:element name="doc" type="x:attRef"/>
        </xsd:schema>
        """
        #expect(!compiles(schema), "qualified attributes land in XSI; xsi: Not Allowed")
    }

    @Test("attKb018: same schema with unqualified attributes (no-namespace) stays valid")
    func test_unqualifiedAttributesValid() {
        let schema = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                    targetNamespace="\(xsi)" xmlns:x="\(xsi)">
          <xsd:attributeGroup name="attG">
            <xsd:attribute name="aga1"/>
            <xsd:attribute name="aga2"/>
          </xsd:attributeGroup>
          <xsd:complexType name="attRef">
            <xsd:attributeGroup ref="x:attG"/>
          </xsd:complexType>
          <xsd:element name="doc" type="x:attRef"/>
        </xsd:schema>
        """
        #expect(compiles(schema), "unqualified attributes land in no namespace, not XSI")
    }

    @Test("attKc018: local unqualified attributes targeting XSI stay valid")
    func test_localUnqualifiedAttributesValid() {
        let schema = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                    targetNamespace="\(xsi)" xmlns:x="\(xsi)">
          <xsd:complexType name="attRef">
            <xsd:attribute name="ca1"/>
            <xsd:attribute name="ca2"/>
          </xsd:complexType>
          <xsd:element name="doc" type="x:attRef"/>
        </xsd:schema>
        """
        #expect(compiles(schema), "local unqualified attributes are in no namespace")
    }

    @Test("a single local attribute with form=qualified into XSI is rejected")
    func test_localFormQualifiedIntoXSIRejected() {
        let schema = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="\(xsi)">
          <xsd:complexType name="attRef">
            <xsd:attribute name="ca1" form="qualified"/>
          </xsd:complexType>
          <xsd:element name="doc" type="attRef"/>
        </xsd:schema>
        """
        #expect(!compiles(schema), "form=qualified puts ca1 into XSI; xsi: Not Allowed")
    }

    @Test("the same qualified attribute targeting a non-XSI namespace is valid")
    func test_qualifiedAttributeOutsideXSIValid() {
        let schema = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                    targetNamespace="urn:ok" attributeFormDefault="qualified">
          <xsd:complexType name="attRef">
            <xsd:attribute name="ca1"/>
          </xsd:complexType>
          <xsd:element name="doc" type="attRef"/>
        </xsd:schema>
        """
        #expect(compiles(schema), "qualifying into a non-XSI namespace is fine")
    }
}
