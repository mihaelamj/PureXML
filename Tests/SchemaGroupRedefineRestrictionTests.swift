@testable import PureXML
import Testing

/// A non-self-referencing model group redefined inside `xs:redefine` must be a valid
/// restriction of the group it redefines (XSD 1.0 cos-group-restrict / src-redefine
/// 6.1.2). Adding content the original cannot produce, or dropping a required member
/// so the language widens, is rejected; a genuine restriction is accepted. The
/// order-preserving Recurse rule applies even to `xs:all`, so reordering an `all` is
/// rejected (W3C schL5), while a base with a `maxOccurs=0` member is left unjudged to
/// avoid the contested pointless-particle case (W3C mgO013).
@Suite("redefined model group restriction")
struct SchemaGroupRedefineRestrictionTests {
    private func redefine(group body: String, base: String) throws -> PureXML.Schema.Document {
        let main = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:redefine schemaLocation='b.xsd'><xs:group name='g'>\(body)</xs:group></xs:redefine>"
            + "<xs:complexType name='t'><xs:group ref='g'/></xs:complexType>"
            + "<xs:element name='e' type='t'/></xs:schema>"
        let baseDoc = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:group name='g'>\(base)</xs:group>"
            + "<xs:complexType name='b'><xs:group ref='g'/></xs:complexType></xs:schema>"
        return try PureXML.Schema.Document(main, schemaLoader: { _ in baseDoc })
    }

    @Test("adding required content to an empty base group is rejected")
    func test_addRequiredToEmptyRejected() throws {
        #expect(throws: (any Error).self) {
            try redefine(
                group: "<xs:sequence><xs:element name='a' type='xs:string'/></xs:sequence>",
                base: "<xs:sequence/>",
            )
        }
    }

    @Test("dropping a required member from an all group is rejected")
    func test_dropRequiredFromAllRejected() throws {
        #expect(throws: (any Error).self) {
            try redefine(
                group: "<xs:all><xs:element name='a' type='xs:string'/></xs:all>",
                base: "<xs:all><xs:element name='a' type='xs:string'/><xs:element name='b' type='xs:string'/></xs:all>",
            )
        }
    }

    @Test("reordering an all group is rejected (order-preserving Recurse)")
    func test_reorderAllRejected() throws {
        #expect(throws: (any Error).self) {
            try redefine(
                group: "<xs:all><xs:element name='b' type='xs:string'/><xs:element name='a' type='xs:string'/></xs:all>",
                base: "<xs:all><xs:element name='a' type='xs:string'/><xs:element name='b' type='xs:string'/></xs:all>",
            )
        }
    }

    @Test("dropping an optional member is a valid restriction")
    func test_dropOptionalAccepted() throws {
        _ = try redefine(
            group: "<xs:sequence><xs:element name='a' type='xs:string'/></xs:sequence>",
            base: "<xs:sequence><xs:element name='a' type='xs:string'/><xs:element name='b' type='xs:string' minOccurs='0'/></xs:sequence>",
        )
    }

    @Test("re-enabling a maxOccurs=0 base member is left unjudged and accepted")
    func test_pointlessParticleBaseAccepted() throws {
        _ = try redefine(
            group: "<xs:all><xs:element name='a' type='xs:string'/></xs:all>",
            base: "<xs:all><xs:element name='a' type='xs:string' minOccurs='0' maxOccurs='0'/></xs:all>",
        )
    }

    @Test("an unchanged group redefinition is a valid restriction")
    func test_identityAccepted() throws {
        _ = try redefine(
            group: "<xs:sequence><xs:element name='a' type='xs:string'/></xs:sequence>",
            base: "<xs:sequence><xs:element name='a' type='xs:string'/></xs:sequence>",
        )
    }
}
