@testable import PureXML
import Testing

/// xs:string has whiteSpace="preserve", so a simple-content value keeps its
/// leading/trailing and whitespace-only content; validation no longer trims it
/// before the facet runs (#147, XSTS reI set). Element-only content still
/// ignores indentation whitespace.
@Suite("String content whitespace is preserved")
struct SchemaStringWhitespaceTests {
    private func patternSchema(_ pattern: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v">
            <xs:simpleType><xs:restriction base="xs:string"><xs:pattern value="\(pattern)"/></xs:restriction></xs:simpleType>
          </xs:element>
        </xs:schema>
        """)
    }

    @Test("A tab-only value matches the \\t pattern (whitespace preserved)")
    func test_tabPreserved() throws {
        #expect(try patternSchema(#"\t"#).validate("<v>&#x9;</v>").isEmpty)
    }

    @Test("A length facet on string counts preserved whitespace")
    func test_lengthCountsWhitespace() throws {
        let doc = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v">
            <xs:simpleType><xs:restriction base="xs:string"><xs:length value="3"/></xs:restriction></xs:simpleType>
          </xs:element>
        </xs:schema>
        """)
        #expect(try doc.validate("<v> a </v>").isEmpty) // space,a,space = 3 chars
        #expect(try !doc.validate("<v>a</v>").isEmpty) // 1 char
    }

    @Test("Element-only content still ignores indentation whitespace")
    func test_elementOnlyIgnoresWhitespace() throws {
        let doc = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="r">
            <xs:complexType><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """)
        #expect(try doc.validate("<r>\n  <a>x</a>\n</r>").isEmpty)
    }
}
