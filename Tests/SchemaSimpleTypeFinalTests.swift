@testable import PureXML
import Testing

@Suite("XSD simple-type final: list/union derivation (st-props-correct)")
struct SchemaSimpleTypeFinalTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    private func base(_ final: String) -> String {
        "<xs:simpleType name=\"T\" final=\"\(final)\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
    }

    private let listOfT = "<xs:simpleType name=\"L\"><xs:list itemType=\"T\"/></xs:simpleType>"
    private let unionOfT = "<xs:simpleType name=\"U\"><xs:union memberTypes=\"T\"/></xs:simpleType>"

    @Test("A type final for 'list' may not be a list item type")
    func test_finalListRejected() {
        #expect(!compiles(base("list") + listOfT))
        #expect(!compiles(base("#all") + listOfT))
    }

    @Test("A type final for 'union' may not be a union member type")
    func test_finalUnionRejected() {
        #expect(!compiles(base("union") + unionOfT))
        #expect(!compiles(base("#all") + unionOfT))
    }

    @Test("final restricts only the named direction")
    func test_finalDirectionScoped() {
        // final='list' does not forbid being a union member.
        #expect(compiles(base("list") + unionOfT))
        // final='union' does not forbid being a list item.
        #expect(compiles(base("union") + listOfT))
        // final='restriction' forbids neither list nor union derivation.
        #expect(compiles(base("restriction") + listOfT))
        #expect(compiles(base("restriction") + unionOfT))
    }

    @Test("A type with no final is usable in a list or union")
    func test_noFinalAccepted() {
        let plain = "<xs:simpleType name=\"T\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
        #expect(compiles(plain + listOfT))
        #expect(compiles(plain + unionOfT))
    }

    /// A user type sharing a built-in's local name (here `string`, `final="list"`)
    /// must not be confused with a reference to the built-in `xs:string`: a list of
    /// `xs:string` is valid because the built-in's final is empty. The reference is
    /// matched only when it resolves to the schema's own namespace.
    @Test("A built-in itemType is not confused with a same-named final user type")
    func test_builtinNameNotConfused() {
        #expect(compiles(
            "<xs:simpleType name=\"string\" final=\"list\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
                + "<xs:simpleType name=\"L\"><xs:list itemType=\"xs:string\"/></xs:simpleType>",
        ))
        #expect(compiles(
            "<xs:simpleType name=\"string\" final=\"union\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
                + "<xs:simpleType name=\"U\"><xs:union memberTypes=\"xs:string\"/></xs:simpleType>",
        ))
    }
}
