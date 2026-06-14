@testable import PureXML
import Testing

/// Content-model order and cardinality for the derivation contexts whose model
/// the set-membership table cannot express: a `simpleContent` derivation (facets
/// and attributes, never a model group). Complements the complexContent and
/// shorthand-complexType order tests in `SchemaStructureTests` (the ctD family).
@Suite("Schema content order")
struct SchemaContentOrderTests {
    private func rejects(_ body: String) -> Bool {
        do {
            _ = try PureXML.Schema.Document("""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            \(body)
            </xs:schema>
            """)
            return false
        } catch {
            return true
        }
    }

    private func simpleContent(_ body: String) -> String {
        #"<xs:complexType name="t"><xs:simpleContent>\#(body)</xs:simpleContent></xs:complexType>"#
    }

    @Test("a simpleContent derivation may not contain a model group")
    func test_noModelGroup() {
        #expect(rejects(simpleContent(#"<xs:extension base="xs:string"><xs:sequence/></xs:extension>"#)))
        #expect(rejects(simpleContent(#"<xs:restriction base="xs:string"><xs:choice/></xs:restriction>"#)))
    }

    @Test("a simpleContent extension may not carry facets or a simpleType")
    func test_extensionNoFacets() {
        #expect(rejects(simpleContent(#"<xs:extension base="xs:string"><xs:maxLength value="3"/></xs:extension>"#)))
    }

    @Test("a simpleContent derivation's attributes and anyAttribute must be ordered")
    func test_attributeOrder() {
        #expect(rejects(simpleContent(#"<xs:extension base="xs:string"><xs:anyAttribute/><xs:anyAttribute/></xs:extension>"#)))
        #expect(rejects(simpleContent(#"<xs:restriction base="xs:string"><xs:anyAttribute/><xs:attribute name="a"/></xs:restriction>"#)))
    }

    @Test("well-formed simpleContent derivations compile")
    func test_valid() {
        #expect(!rejects(simpleContent(#"<xs:extension base="xs:string"><xs:attribute name="a" type="xs:string"/></xs:extension>"#)))
        #expect(!rejects(simpleContent(#"<xs:restriction base="xs:string"><xs:maxLength value="3"/><xs:attribute name="a"/></xs:restriction>"#)))
    }
}
