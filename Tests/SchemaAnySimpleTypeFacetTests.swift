@testable import PureXML
import Testing

/// A constraining facet may not be applied where a `simpleContent` restriction's base
/// chain resolves to `xs:anySimpleType`, the ur simple type, which carries no
/// constraining facets (XSD Part 2 §3.2.1, W3C stZ010). A base that bottoms at a real
/// built-in or a user simple type still admits its applicable facets.
@Suite("anySimpleType simpleContent facet applicability")
struct SchemaAnySimpleTypeFacetTests {
    private func compile(_ schema: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document(schema)
    }

    private func chain(base: String, facet: String) -> String {
        "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:complexType name='t1'><xs:simpleContent><xs:extension base='\(base)'/></xs:simpleContent></xs:complexType>"
            + "<xs:complexType name='t2'><xs:simpleContent><xs:restriction base='t1'>\(facet)</xs:restriction></xs:simpleContent></xs:complexType>"
            + "</xs:schema>"
    }

    @Test("a facet on an anySimpleType-based simpleContent restriction is rejected")
    func test_facetOnAnySimpleTypeRejected() throws {
        #expect(throws: (any Error).self) {
            try compile(chain(base: "xs:anySimpleType", facet: "<xs:minLength value='1'/>"))
        }
    }

    @Test("minLength on a string-based simpleContent restriction is valid")
    func test_facetOnStringAccepted() throws {
        _ = try compile(chain(base: "xs:string", facet: "<xs:minLength value='1'/>"))
    }

    @Test("maxInclusive on an int-based simpleContent restriction is valid")
    func test_facetOnIntAccepted() throws {
        _ = try compile(chain(base: "xs:int", facet: "<xs:maxInclusive value='5'/>"))
    }

    @Test("an anySimpleType extension with no facet restriction is valid")
    func test_anySimpleTypeWithoutFacetAccepted() throws {
        _ = try compile(
            "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
                + "<xs:complexType name='t1'><xs:simpleContent><xs:extension base='xs:anySimpleType'/></xs:simpleContent></xs:complexType>"
                + "</xs:schema>",
        )
    }
}
