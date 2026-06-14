@testable import PureXML
import Testing

@Suite("XSD restriction: content-free and substitution-group order")
struct XSDRestrictionContentFreeAndOrderTests {
    private func compiles(_ source: String) -> Bool {
        (try? PureXML.Schema.Document(source)) != nil
    }

    @Test("A never-occurring (maxOccurs=0) group restricts an emptiable base, but not a required one")
    func test_contentFreeRestriction() {
        // particlesW006: a sequence with maxOccurs=0 accepts only the empty sequence,
        // whatever its members' own occurrences, so it validly restricts a base that
        // also never occurs (or is otherwise emptiable).
        let base = "<xs:complexType name=\"B\"><xs:sequence minOccurs=\"0\" maxOccurs=\"0\">"
            + "<xs:element name=\"e1\" maxOccurs=\"3\"/><xs:element name=\"e2\" maxOccurs=\"3\"/></xs:sequence></xs:complexType>"
        let restriction = "<xs:complexType name=\"R\"><xs:complexContent><xs:restriction base=\"B\">"
            + "<xs:sequence minOccurs=\"0\" maxOccurs=\"0\">"
            + "<xs:element name=\"e1\" minOccurs=\"4\" maxOccurs=\"5\"/><xs:element name=\"e2\" minOccurs=\"3\" maxOccurs=\"3\"/></xs:sequence>"
            + "</xs:restriction></xs:complexContent></xs:complexType>"
        #expect(compiles("<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">\(base)\(restriction)</xs:schema>"))
        // But a content-free restriction of a REQUIRED base is invalid: the base
        // requires content the empty restriction cannot supply.
        let requiredBase = "<xs:complexType name=\"B\"><xs:sequence><xs:element name=\"e1\"/></xs:sequence></xs:complexType>"
        let emptyRestriction = "<xs:complexType name=\"R\"><xs:complexContent><xs:restriction base=\"B\">"
            + "<xs:sequence minOccurs=\"0\" maxOccurs=\"0\"><xs:element name=\"e1\"/></xs:sequence>"
            + "</xs:restriction></xs:complexContent></xs:complexType>"
        #expect(!compiles("<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">\(requiredBase)\(emptyRestriction)</xs:schema>"))
    }

    @Test("A choice of substitution-group members restricts a reference to the head, in declaration order")
    func test_substitutionGroupChoiceOrder() {
        // elemZ027a: a ref to a head expands to choice(head, m1, m2) in declaration
        // order; a derived choice(m1, m2) maps onto it in order (RecurseLax).
        let decls = "<xs:element name=\"head\"/><xs:element name=\"m1\" substitutionGroup=\"head\"/>"
            + "<xs:element name=\"m2\" substitutionGroup=\"head\"/>"
        let base = "<xs:complexType name=\"base\"><xs:sequence><xs:element ref=\"head\"/></xs:sequence></xs:complexType>"
        func derived(_ first: String, _ second: String) -> String {
            "<xs:complexType name=\"derived\"><xs:complexContent><xs:restriction base=\"base\"><xs:sequence>"
                + "<xs:choice><xs:element ref=\"\(first)\"/><xs:element ref=\"\(second)\"/></xs:choice>"
                + "</xs:sequence></xs:restriction></xs:complexContent></xs:complexType>"
        }
        let head = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">\(decls)\(base)"
        #expect(compiles(head + derived("m1", "m2") + "</xs:schema>"))
    }

    @Test("Reordering a base choice's branches is not a valid restriction (RecurseLax is order-preserving)")
    func test_choiceReorderRejected() {
        // particlesT002: choice(c2, c1) is NOT a valid restriction of choice(c1, c2).
        let base = "<xs:complexType name=\"B\"><xs:sequence><xs:choice>"
            + "<xs:element name=\"c1\"/><xs:element name=\"c2\"/></xs:choice><xs:element name=\"foo\"/></xs:sequence></xs:complexType>"
        let reordered = "<xs:complexType name=\"R\"><xs:complexContent><xs:restriction base=\"B\"><xs:sequence><xs:choice>"
            + "<xs:element name=\"c2\"/><xs:element name=\"c1\"/></xs:choice><xs:element name=\"foo\"/></xs:sequence>"
            + "</xs:restriction></xs:complexContent></xs:complexType>"
        #expect(!compiles("<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">\(base)\(reordered)</xs:schema>"))
    }
}
