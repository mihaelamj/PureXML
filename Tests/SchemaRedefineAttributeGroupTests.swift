import Testing
@testable import PureXML

/// A redefinition of an attribute group restricts the original (src-redefine), so
/// it may neither eliminate a required attribute nor re-introduce a prohibited one
/// as usable. Keeping a required attribute, and re-declaring a prohibited attribute
/// as prohibited, are both valid (W3C attgZ002/attgZ003, schT3).
@Suite("redefined attribute group restriction")
struct SchemaRedefineAttributeGroupTests {
    private func redefine(group body: String, base: String) throws -> PureXML.Schema.Document {
        let main = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:redefine schemaLocation='b.xsd'><xs:attributeGroup name='g'>\(body)</xs:attributeGroup></xs:redefine>"
            + "<xs:element name='e'/></xs:schema>"
        let baseDoc = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:attributeGroup name='g'>\(base)</xs:attributeGroup></xs:schema>"
        return try PureXML.Schema.Document(main, schemaLoader: { _ in baseDoc })
    }

    @Test("eliminating a required attribute is rejected")
    func test_dropRequiredRejected() throws {
        #expect(throws: (any Error).self) {
            try redefine(
                group: "<xs:attribute name='b' type='xs:string'/>",
                base: "<xs:attribute name='a' use='required' type='xs:string'/><xs:attribute name='b' type='xs:string'/>",
            )
        }
    }

    @Test("re-introducing a prohibited attribute as usable is rejected")
    func test_reintroduceProhibitedRejected() throws {
        #expect(throws: (any Error).self) {
            try redefine(
                group: "<xs:attribute name='a' type='xs:string'/>",
                base: "<xs:attribute name='a' use='prohibited' type='xs:string'/>",
            )
        }
    }

    @Test("keeping a required attribute and re-prohibiting a prohibited one is valid")
    func test_validRedefinitionAccepted() throws {
        _ = try redefine(
            group: "<xs:attribute name='a' use='required' type='xs:string'/><xs:attribute name='p' use='prohibited' type='xs:string'/>",
            base: "<xs:attribute name='a' use='required' type='xs:string'/><xs:attribute name='p' use='prohibited' type='xs:string'/><xs:attribute name='o' type='xs:string'/>",
        )
    }

    @Test("relaxing a fixed value in the redefinition is rejected")
    func test_relaxFixedRejected() throws {
        #expect(throws: (any Error).self) {
            try redefine(
                group: "<xs:attribute name='a' type='xs:string' default='abc'/>",
                base: "<xs:attribute name='a' type='xs:string' fixed='abc'/>",
            )
        }
    }

    @Test("keeping the same fixed value in the redefinition is valid")
    func test_keepFixedAccepted() throws {
        _ = try redefine(
            group: "<xs:attribute name='a' type='xs:string' fixed='abc'/>",
            base: "<xs:attribute name='a' type='xs:string' fixed='abc'/>",
        )
    }

    @Test("adding an attribute not in the original is rejected (superset)")
    func test_addAttributeRejected() throws {
        #expect(throws: (any Error).self) {
            try redefine(
                group: "<xs:attribute name='a' type='xs:string'/><xs:attribute name='b' type='xs:string'/>",
                base: "<xs:attribute name='a' type='xs:string'/>",
            )
        }
    }

    @Test("declaring a prohibited attribute the base lacks is valid (not a superset)")
    func test_addProhibitedAccepted() throws {
        _ = try redefine(
            group: "<xs:attribute name='a' type='xs:string'/><xs:attribute name='z' use='prohibited' type='xs:string'/>",
            base: "<xs:attribute name='a' type='xs:string'/>",
        )
    }

    @Test("adding an attribute alongside a self-reference is valid")
    func test_addWithSelfReferenceAccepted() throws {
        _ = try redefine(
            group: "<xs:attributeGroup ref='g'/><xs:attribute name='b' type='xs:string'/>",
            base: "<xs:attribute name='a' type='xs:string'/>",
        )
    }

    @Test("a non-self reference injecting a foreign attribute is rejected (attgC028)")
    func test_nonSelfReferenceAddRejected() throws {
        let main = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:redefine schemaLocation='b.xsd'><xs:attributeGroup name='g'>"
            + "<xs:attributeGroup ref='car'/></xs:attributeGroup></xs:redefine>"
            + "<xs:attributeGroup name='car'><xs:attribute name='foo1' type='xs:int'/>"
            + "<xs:attribute name='foo2' type='xs:string'/></xs:attributeGroup>"
            + "<xs:element name='e'/></xs:schema>"
        let baseDoc = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:attributeGroup name='g'><xs:attribute name='att' type='xs:int'/></xs:attributeGroup></xs:schema>"
        #expect(throws: (any Error).self) { try PureXML.Schema.Document(main, schemaLoader: { _ in baseDoc }) }
    }

    @Test("a non-self reference whose attributes are all in the original is valid")
    func test_nonSelfReferenceSubsetAccepted() throws {
        let main = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:redefine schemaLocation='b.xsd'><xs:attributeGroup name='g'>"
            + "<xs:attributeGroup ref='sub'/></xs:attributeGroup></xs:redefine>"
            + "<xs:attributeGroup name='sub'><xs:attribute name='att' type='xs:int'/></xs:attributeGroup>"
            + "<xs:element name='e'/></xs:schema>"
        let baseDoc = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:attributeGroup name='g'><xs:attribute name='att' type='xs:int'/>"
            + "<xs:attribute name='att2' type='xs:string'/></xs:attributeGroup></xs:schema>"
        _ = try PureXML.Schema.Document(main, schemaLoader: { _ in baseDoc })
    }

    @Test("a referenced group with an attribute wildcard is not judged (lenient, no false positive)")
    func test_nonSelfReferenceWildcardLenient() throws {
        let main = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:redefine schemaLocation='b.xsd'><xs:attributeGroup name='g'>"
            + "<xs:attributeGroup ref='car'/></xs:attributeGroup></xs:redefine>"
            + "<xs:attributeGroup name='car'><xs:attribute name='foo1' type='xs:int'/>"
            + "<xs:anyAttribute/></xs:attributeGroup>"
            + "<xs:element name='e'/></xs:schema>"
        let baseDoc = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:attributeGroup name='g'><xs:attribute name='att' type='xs:int'/></xs:attributeGroup></xs:schema>"
        _ = try PureXML.Schema.Document(main, schemaLoader: { _ in baseDoc })
    }

    @Test("re-declaring an attribute the base inherits via a reference is valid")
    func test_redeclareInheritedAccepted() throws {
        let main = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:redefine schemaLocation='b.xsd'><xs:attributeGroup name='g'>"
            + "<xs:attribute name='x' type='xs:string'/></xs:attributeGroup></xs:redefine>"
            + "<xs:element name='e'/></xs:schema>"
        let baseDoc = "<xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'>"
            + "<xs:attributeGroup name='inner'><xs:attribute name='x' type='xs:string'/></xs:attributeGroup>"
            + "<xs:attributeGroup name='g'><xs:attributeGroup ref='inner'/></xs:attributeGroup></xs:schema>"
        _ = try PureXML.Schema.Document(main, schemaLoader: { _ in baseDoc })
    }
}
