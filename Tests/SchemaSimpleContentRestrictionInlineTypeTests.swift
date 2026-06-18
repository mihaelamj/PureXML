import Testing
@testable import PureXML

@Suite("simpleContent restriction inline simpleType")
struct SimpleContentInlineTypeTests {
    @Test("an inline list simpleType is not a restriction of an atomic decimal simpleContent base")
    func test_listInlineTypeOverDecimalBaseRejected() {
        let schema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="B1">
            <xs:simpleContent>
              <xs:extension base="xs:decimal">
                <xs:attribute name="foo"/>
              </xs:extension>
            </xs:simpleContent>
          </xs:complexType>
          <xs:complexType name="C2">
            <xs:simpleContent>
              <xs:restriction base="B1">
                <xs:simpleType>
                  <xs:list itemType="xs:int"/>
                </xs:simpleType>
              </xs:restriction>
            </xs:simpleContent>
          </xs:complexType>
        </xs:schema>
        """

        #expect((try? PureXML.Schema.Document(schema)) == nil)
    }

    @Test("a valid inline atomic restriction becomes the effective simpleContent type")
    func test_validInlineTypeRestrictsInstanceValues() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:t="urn:test" targetNamespace="urn:test">
          <xs:element name="root" type="t:C2"/>
          <xs:complexType name="B1">
            <xs:simpleContent>
              <xs:extension base="xs:decimal"/>
            </xs:simpleContent>
          </xs:complexType>
          <xs:complexType name="C2">
            <xs:simpleContent>
              <xs:restriction base="t:B1">
                <xs:simpleType>
                  <xs:restriction base="xs:integer">
                    <xs:minInclusive value="0"/>
                  </xs:restriction>
                </xs:simpleType>
                <xs:maxInclusive value="10"/>
              </xs:restriction>
            </xs:simpleContent>
          </xs:complexType>
        </xs:schema>
        """)

        #expect(try schema.validate(#"<root xmlns="urn:test">5</root>"#).isEmpty)
        #expect(try !schema.validate(#"<root xmlns="urn:test">1.5</root>"#).isEmpty)
        #expect(try !schema.validate(#"<root xmlns="urn:test">11</root>"#).isEmpty)
    }
}
