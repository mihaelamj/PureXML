import Testing
@testable import PureXML

/// #192 worst-case guard. A content model with nested huge-`maxOccurs` counters (the
/// Z035-class adversarial shape) must validate a large document in bounded work, not
/// blow up the active-configuration set. Before effectively-unbounded finite counters
/// were saturated at their minimum, an 800-child document against this model did not
/// terminate within a minute (the active set grew like `inputLength` raised to the
/// nesting depth); it is now linear. The time limit turns a regression back to the
/// super-linear blowup into a test failure rather than a silent interactive hang.
///
/// This covers the huge-`maxOccurs` case (a maximum the input cannot reach). A model
/// with several MODERATE `maxOccurs` (reachable by the document) nested deeply is not
/// yet bounded to a small constant and remains tracked in #192.
@Suite("XSD content-matcher worst case (#192)")
struct ContentMatcherWorstCaseTests {
    private let hugeMaxOccursModel = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="root"><xs:complexType>
        <xs:sequence maxOccurs="100000"><xs:sequence maxOccurs="100000">
          <xs:choice maxOccurs="100000"><xs:element name="a" type="xs:string" maxOccurs="100000"/></xs:choice>
        </xs:sequence></xs:sequence>
      </xs:complexType></xs:element>
    </xs:schema>
    """

    #if os(WASI)
        @Test("a huge-maxOccurs nested content model validates a large document in bounded work")
    #else
        @Test("a huge-maxOccurs nested content model validates a large document in bounded work", .timeLimit(.minutes(1)))
    #endif
    func test_hugeMaxOccursBounded() throws {
        let document = try PureXML.Schema.Document(hugeMaxOccursModel)
        let valid = "<root>" + String(repeating: "<a>x</a>", count: 10000) + "</root>"
        #expect(try document.validate(valid).isEmpty)
        // A child the model does not admit is still correctly rejected (the saturation
        // does not widen what is accepted), and that decision is also bounded.
        let invalid = "<root>" + String(repeating: "<a>x</a>", count: 5000) + "<b/></root>"
        #expect(try !document.validate(invalid).isEmpty)
    }
}
